import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "chips", "accessPanel", "warnings", "groupToggle"]

  connect() {
    this.sync()
  }

  change() {
    this.sync()
    this.submit()
  }

  toggleGroup(event) {
    const group = event.currentTarget.closest("[data-permission-group]")
    group.querySelectorAll('[data-permission-sets-target="checkbox"]').forEach((checkbox) => {
      checkbox.checked = event.currentTarget.checked
    })
    this.sync()
    this.submit()
  }

  remove(event) {
    const checkbox = this.checkboxTargets.find(
      (candidate) => candidate.dataset.permissionSet === event.currentTarget.dataset.permissionSet
    )
    if (checkbox) checkbox.checked = false
    this.sync()
    this.submit()
  }

  sync() {
    const selected = new Set(this.checkboxTargets.filter((checkbox) => checkbox.checked).map((checkbox) => checkbox.dataset.permissionSet))

    this.checkboxTargets.forEach((checkbox) => {
      const implied = (checkbox.dataset.implies || "").split(",").filter(Boolean)
      implied.forEach((permissionSet) => {
        const impliedCheckbox = this.checkboxTargets.find((candidate) => candidate.dataset.permissionSet === permissionSet)
        if (impliedCheckbox && checkbox.checked) {
          impliedCheckbox.checked = true
          impliedCheckbox.tabIndex = -1
          impliedCheckbox.classList.add("pointer-events-none", "opacity-60")
          impliedCheckbox.closest("label").classList.add("opacity-60")
        }
      })
    })

    this.checkboxTargets.forEach((checkbox) => {
      const isImplied = this.checkboxTargets.some((candidate) => candidate.checked && (candidate.dataset.implies || "").split(",").includes(checkbox.dataset.permissionSet))
      if (!isImplied) {
        checkbox.tabIndex = 0
        checkbox.classList.remove("pointer-events-none", "opacity-60")
        checkbox.closest("label").classList.remove("opacity-60")
      }
    })

    this.renderChips()
    this.renderAccess()
    this.updateGroupToggles()
  }

  renderChips() {
    this.chipsTarget.replaceChildren()
    this.checkboxTargets.filter((checkbox) => checkbox.checked).forEach((checkbox) => {
      const chip = document.createElement("span")
      chip.className = "inline-flex items-center gap-1 rounded-md border bg-gray-25 px-2 py-1 text-sm"
      chip.textContent = checkbox.closest("label").querySelector("span").textContent

      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "text-muted hover:text-danger"
      remove.title = "Remove"
      remove.setAttribute("aria-label", `Remove ${chip.textContent}`)
      remove.dataset.action = "click->permission-sets#remove"
      remove.dataset.permissionSet = checkbox.dataset.permissionSet
      remove.textContent = "×"
      chip.append(remove)
      this.chipsTarget.append(chip)
    })
  }

  renderAccess() {
    const areas = new Set()
    const warnings = new Set()
    this.checkboxTargets.filter((checkbox) => checkbox.checked).forEach((checkbox) => {
      JSON.parse(checkbox.dataset.areas || "[]").forEach((area) => areas.add(area))
      if (checkbox.dataset.warning) warnings.add(checkbox.dataset.warning)
    })
    this.accessPanelTarget.replaceChildren(...[...areas].map((area) => {
      const item = document.createElement("li")
      item.textContent = area
      return item
    }))
    this.warningsTarget.replaceChildren(...[...warnings].map((warning) => {
      const item = document.createElement("p")
      item.className = "text-warning mb-1"
      item.textContent = `Warning: ${warning}`
      return item
    }))
  }

  updateGroupToggles() {
    this.groupToggleTargets.forEach((toggle) => {
      const checkboxes = toggle.closest("[data-permission-group]").querySelectorAll('[data-permission-sets-target="checkbox"]')
      toggle.checked = [...checkboxes].every((checkbox) => checkbox.checked)
    })
  }

  submit() {
    this.element.closest("form")?.requestSubmit()
  }
}