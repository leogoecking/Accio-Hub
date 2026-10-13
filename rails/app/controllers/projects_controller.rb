class ProjectsController < StudioController
  before_action :load_studio, only: %i[index show new edit]
  rescue_from ProjectCommands::Conflict, ActiveRecord::StaleObjectError, with: :project_conflict
  rescue_from ProjectCommands::InvalidIntent, ArgumentError, KeyError, ActiveRecord::RecordInvalid, with: :invalid_project

  rescue_from ActiveRecord::RecordNotFound, with: :missing_project

  def index
    @filters = library.filters
    @projects = library.select(search: params[:q])
    @pending_counts = Current.user.tasks.where(status: "pending").group(:project_id).count
    if params[:dialog].present?
      @modal_src = params[:dialog] == "new" ? new_project_path : edit_project_path(Current.user.projects.find_by!(uid: PublicUid.decode(params[:dialog])))
    end
  end

  def show
    @project = owned_project
    @tab = params.fetch(:tab, "overview")
    return head :not_found unless %w[overview tasks knowledge references].include?(@tab)
    @tasks = Current.user.tasks.where(project: @project).order(position: :desc, uid: :asc).to_a
    if params[:task_dialog].present?
      @task_modal_src = params[:task_dialog] == "new" ? new_project_task_path(@project) : edit_project_task_path(@project, Current.user.tasks.where(project: @project).find_by!(uid: PublicUid.decode(params[:task_dialog])))
    end
    @references = Current.user.project_references.where(project: @project).order(:position, :uid).to_a
  end

  def new
    return redirect_to projects_path(dialog: "new") unless request.headers["Turbo-Frame"] == "project-modal"
    @project = Current.user.projects.build(color: "#8befcc")
    @intent = commands.issue
    render :form
  end

  def edit
    @project = owned_project
    return redirect_to projects_path(dialog: @project.to_param) unless request.headers["Turbo-Frame"] == "project-modal"
    if @project.status == "archived"
      @unavailable_message = "Projeto arquivado é somente leitura. Use restauração na Biblioteca."
      return render :unavailable_form, status: :conflict
    end
    render :form
  end

  def create
    project = commands.create(params[:intent], project_params)
    render json: { message: "Projeto criado e confirmado.", project: snapshot(project) }
  end

  def update
    project = commands.change(route_uid, version: version, operation: "edit", attributes: project_params)
    render json: { message: "Alterações salvas.", project: snapshot(project) }
  end

  def command
    values = params.permit(:favorite, :status).to_h
    values["favorite"] = { "true" => true, "false" => false, true => true, false => false }.fetch(values["favorite"]) if values.key?("favorite")
    project = commands.change(route_uid, version: version, operation: params[:operation], attributes: values)
    render json: { message: "Projeto atualizado.", project: snapshot(project) }
  end

  def filters
    result = library.update_filters(params.require(:filters).permit(*ProjectLibrary::FILTERS).to_h, version: version)
    presentation_cookie(result[:appearance])
    render json: result.merge(message: "Filtros salvos.")
  end

  private

  def commands
    @commands ||= ProjectCommands.new(Current.user)
  end

  def library
    @library ||= ProjectLibrary.new(Current.user)
  end

  def route_uid
    PublicUid.decode(params[:uid])
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  def owned_project
    Current.user.projects.find_by!(uid: route_uid)
  end

  def version
    value = params[:version]
    return value if value.is_a?(Integer) && value >= 0
    value.to_i if value.is_a?(String) && value.match?(/\A\d+\z/)
  end

  def project_params
    params.require(:project).permit(*ProjectCommands::FIELDS).to_h
  end

  def snapshot(project)
    project.attributes.slice(*ProjectCommands::FIELDS, "status", "favorite", "lock_version").merge("path" => project_path(project), "display_color" => helpers.project_color(project))
  end

  def project_conflict(error)
    project = Current.user.projects.find_by(uid: route_uid) if params[:uid]
    render json: { error: "project_conflict", message: error.message, project: project && snapshot(project) }, status: :conflict
  end

  def missing_project
    if request.headers["Turbo-Frame"] == "project-modal"
      @unavailable_message = "Projeto não encontrado. Volte à Biblioteca para conferir seus projetos."
      render :unavailable_form, status: :not_found
    elsif request.format.json?
      render json: { error: "not_found", message: "Projeto não encontrado" }, status: :not_found
    else
      load_studio unless @appearance
      render :missing, status: :not_found
    end
  end

  def invalid_project(error)
    message = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.join(". ") : error.message
    render json: { error: "invalid_project", message: message }, status: :unprocessable_entity
  end
end
