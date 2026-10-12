import "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"
import StudioController from "controllers/studio_controller"

const application = Application.start()
application.register("studio", StudioController)
