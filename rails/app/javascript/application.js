import "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"
import StudioController from "controllers/studio_controller"

const application = Application.start()
application.register("studio", StudioController)

window.Stimulus = application
import ProjectFormController from "controllers/project_form_controller"
application.register("project-form", ProjectFormController)
import ProjectCommandController from "controllers/project_command_controller"
application.register("project-command", ProjectCommandController)
import ProjectLibraryController from "controllers/project_library_controller"
application.register("project-library", ProjectLibraryController)
import ProjectModalController from "controllers/project_modal_controller"
application.register("project-modal", ProjectModalController)
import ProjectTabsController from "controllers/project_tabs_controller"
application.register("project-tabs", ProjectTabsController)
import TaskFormController from 'controllers/task_form_controller'
application.register('task-form', TaskFormController)
import TaskModalController from 'controllers/task_modal_controller'
application.register('task-modal', TaskModalController)
import TaskCommandController from 'controllers/task_command_controller'
application.register('task-command', TaskCommandController)
import TaskSearchController from 'controllers/task_search_controller'
application.register('task-search', TaskSearchController)
import ReferenceFormController from 'controllers/reference_form_controller'
application.register('reference-form', ReferenceFormController)
import ReferenceModalController from 'controllers/reference_modal_controller'
application.register('reference-modal', ReferenceModalController)
