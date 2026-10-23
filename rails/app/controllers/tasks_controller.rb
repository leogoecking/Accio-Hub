class TasksController < StudioController
  before_action :task_shell, only: %i[index new edit]
  rescue_from TaskCommands::Conflict, ActiveRecord::StaleObjectError, with: :task_conflict
  rescue_from TaskCommands::InvalidIntent, ArgumentError, KeyError, ActiveRecord::RecordInvalid, with: :invalid_task
  rescue_from ActiveRecord::RecordNotFound, with: :missing_task

  def index
    @tasks = Current.user.tasks.includes(:project).order(position: :desc, uid: :asc)
    @task_modal_src = params[:dialog] == "new" ? new_task_path : edit_task_path(Current.user.tasks.find_by!(uid: decode(params[:dialog]))) if params[:dialog].present?
  end

  def search
    term = params[:q].to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.strip
    @tasks = Current.user.tasks.includes(:project).order(position: :desc, uid: :asc).to_a.select do |task|
      term.present? && "#{task.title} #{task.project&.name}".unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.include?(term)
    end.first(9)
    render partial: "search", layout: false
  end

  def new
    @context = context_project
    return redirect_to(@context ? project_path(@context, tab: "tasks", task_dialog: "new") : tasks_path(dialog: "new")) unless task_frame?
    editable!(@context)
    @task = Current.user.tasks.build(project: @context)
    @intent = commands.issue(context: @context&.uid)
    prepare_form
  end

  def edit
    @context = context_project
    @task = owned_task
    return redirect_to(@context ? project_path(@context, tab: "tasks", task_dialog: @task.to_param) : tasks_path(dialog: @task.to_param)) unless task_frame?
    editable!(@task.project)
    prepare_form
  end

  def create
    task = commands.create(params[:intent], task_params, context: context_project&.uid, destination: destination)
    render json: { message: "Tarefa criada e confirmada.", task: snapshot(task) }
  end

  def update
    task = commands.change(decode(params[:uid]), version: version, operation: "edit", attributes: task_params, context: context_project&.uid, destination: destination)
    render json: { message: "Tarefa salva.", task: snapshot(task) }
  end

  def status
    task = commands.change(decode(params[:uid]), version: version, operation: "status", attributes: { "status" => params[:status] }, context: context_project&.uid)
    render json: { message: task.status == "completed" ? "Tarefa concluída." : "Tarefa reaberta.", task: snapshot(task) }
  end

  private

  def task_shell
    @page = "tasks"
    load_studio
  end

  def task_frame?
    request.headers["Turbo-Frame"] == "task-modal"
  end

  def commands
    @commands ||= TaskCommands.new(Current.user)
  end

  def decode(value)
    PublicUid.decode(value)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  def context_project
    @context_project ||= Current.user.projects.find_by!(uid: decode(params[:project_uid])) if params[:project_uid]
  end

  def owned_task
    scope = Current.user.tasks
    scope = scope.where(project: context_project) if context_project
    scope.find_by!(uid: decode(params[:uid]))
  end

  def editable!(project)
    raise TaskCommands::ArchivedProject, "Projeto arquivado é somente leitura. Restaure-o na Biblioteca." if project&.status == "archived"
  end

  def destination
    return nil if params[:project_uid]
    fields = params.require(:task)
    return action_name == "update" ? owned_task.project&.uid : nil unless fields.key?(:project_uid)
    value = fields[:project_uid]
    raise ActiveRecord::RecordNotFound unless value.nil? || value.is_a?(String)
    value.present? ? decode(value) : nil
  end

  def task_params
    params.require(:task).permit(*TaskCommands::FIELDS).to_h
  end

  def version
    value = params[:version]
    return value if value.is_a?(Integer) && value >= 0
    value.to_i if value.is_a?(String) && value.match?(/\A\d+\z/)
  end

  def prepare_form
    @choices = Current.user.projects.where.not(status: "archived").order(:name)
    render :form
  end

  def snapshot(task)
    task.attributes.slice("title", "priority", "status", "lock_version").merge("project_uid" => task.project&.to_param, "project_name" => task.project&.name || "Pessoal", "editable" => task.project&.status != "archived", "path" => tasks_path(dialog: task.to_param))
  end

  def task_conflict(error)
    if task_frame?
      @unavailable_message = error.message
      render :unavailable_form, status: :conflict
    else
      task = owned_task if params[:uid]
      render json: { error: "task_conflict", reason: error.is_a?(TaskCommands::ArchivedProject) ? "project_archived" : "stale", message: error.message, task: task && snapshot(task) }, status: :conflict
    end
  end

  def invalid_task(error)
    message = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.join(". ") : error.message
    render json: { error: "invalid_task", message: message }, status: :unprocessable_entity
  end

  def missing_task
    if task_frame?
      @unavailable_message = "Tarefa ou projeto não encontrado. Confira seus registros."
      render :unavailable_form, status: :not_found
    elsif request.format.json?
      render json: { error: "not_found", message: "Tarefa ou projeto não encontrado" }, status: :not_found
    else
      render :missing, status: :not_found
    end
  end
end
