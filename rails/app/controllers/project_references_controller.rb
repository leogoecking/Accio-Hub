class ProjectReferencesController < StudioController
  before_action :load_studio, only: %i[new edit]
  rescue_from ReferenceCommands::Conflict, ActiveRecord::StaleObjectError, with: :reference_conflict
  rescue_from ReferenceCommands::InvalidIntent, ArgumentError, ActiveRecord::RecordInvalid, with: :invalid_reference
  rescue_from ActiveRecord::RecordNotFound, with: :missing_reference

  def new
    @project = owned_project
    return redirect_to project_path(@project, tab: "references", reference_dialog: "new") unless reference_frame?
    editable!
    @reference = @project.project_references.build
    @intent = commands.issue(context: @project.uid)
    render :form
  end

  def edit
    @project = owned_project
    @reference = owned_reference
    return redirect_to project_path(@project, tab: "references", reference_dialog: @reference.to_param) unless reference_frame?
    editable!
    render :form
  end

  def create
    @project = owned_project
    reference = commands.create(params[:intent], reference_params, context: @project.uid)
    render json: { message: "Referência criada e confirmada.", reference: snapshot(reference) }
  end

  def update
    @project = owned_project
    reference = commands.change(decode(params[:uid]), version: version, attributes: reference_params, context: @project.uid)
    render json: { message: "Referência salva.", reference: snapshot(reference) }
  end

  private

  def commands
    @commands ||= ReferenceCommands.new(Current.user)
  end

  def reference_frame?
    request.headers["Turbo-Frame"] == "reference-modal"
  end

  def decode(value)
    PublicUid.decode(value)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  def owned_project
    Current.user.projects.find_by!(uid: decode(params[:project_uid]))
  end

  def owned_reference
    @project.project_references.where(user: Current.user).find_by!(uid: decode(params[:uid]))
  end

  def editable!
    raise ReferenceCommands::ArchivedProject, "Projeto arquivado é somente leitura. Restaure-o na Biblioteca." if @project.status == "archived"
  end

  def reference_params
    fields = params.require(:reference)
    raise ArgumentError, "Campos da referência devem ser texto" unless ReferenceCommands::FIELDS.all? { |field| !fields.key?(field) || fields[field].is_a?(String) }
    fields.permit(*ReferenceCommands::FIELDS).to_h
  end

  def version
    value = params[:version]
    return value if value.is_a?(Integer) && value >= 0
    value.to_i if value.is_a?(String) && value.match?(/\A\d+\z/)
  end

  def snapshot(reference)
    reference.attributes.slice(*ReferenceCommands::FIELDS, "lock_version").merge("editable" => reference.project.status != "archived")
  end

  def reference_conflict(error)
    if reference_frame?
      @unavailable_message = error.message
      render :unavailable_form, status: :conflict
    else
      @project.reload
      reference = owned_reference if params[:uid]
      render json: { error: "reference_conflict", reason: error.is_a?(ReferenceCommands::ArchivedProject) ? "project_archived" : "stale", message: error.message, reference: reference && snapshot(reference) }, status: :conflict
    end
  end

  def invalid_reference(error)
    message = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.join(". ") : error.message
    render json: { error: "invalid_reference", message: message }, status: :unprocessable_entity
  end

  def missing_reference
    if reference_frame?
      @unavailable_message = "Referência ou projeto não encontrado. Confira seus registros."
      render :unavailable_form, status: :not_found
    elsif request.format.json?
      render json: { error: "not_found", message: "Referência ou projeto não encontrado" }, status: :not_found
    else
      render "projects/missing", status: :not_found
    end
  end
end
