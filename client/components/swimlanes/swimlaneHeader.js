BlazeComponent.extendComponent({
  editTitle(evt) {
    evt.preventDefault();
    const newTitle = this.childComponents('inlinedForm')[0].getValue().trim();
    const swimlane = this.currentData();
    if (newTitle) {
      swimlane.rename(newTitle.trim());
    }
  },
  addSwimlane(evt) {
    evt.preventDefault();
    titleInput = this.find('.swimlane-name-input');
    const title = titleInput.value.trim();
    if (title) {
      Swimlanes.insert({
        title,
        boardId: Session.get('currentBoard'),
        sort: $('.swimlane').length,
      });
      titleInput.value = '';
      titleInput.focus();
    }
  },

  events() {
    return [{
      'click .js-open-swimlane-menu': Popup.open('swimlaneAction'),
      submit: this.editTitle,
      addnew: this.addSwimlane,
    }];
  },
}).register('swimlaneHeader');

Template.swimlaneActionPopup.events({
  'click .js-close-swimlane' (evt) {
    evt.preventDefault();
    this.archive();
    Popup.close();
  },
});
