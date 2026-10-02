import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit() {
    this.element.closest("form").requestSubmit()
  }

  remove(event) {
    const permissionSet = event.currentTarget.dataset.permissionSet
    const checkbox = this.element.querySelector(
      `[data-role-permissions-target="checkbox"][value="${permissionSet}"]`
    )

    if (checkbox) checkbox.checked = false
    this.submit()
  }
}