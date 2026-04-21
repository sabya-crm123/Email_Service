import { LightningElement, api, track } from 'lwc';
import getEmailTemplates from '@salesforce/apex/EmailTemplateController.getEmailTemplates';
import getTemplateBody from '@salesforce/apex/EmailTemplateController.getTemplateBody';

export default class ComposeMaximized extends LightningElement {

    @api composeData = {};
    @api fileUpload  = [];

    @track localData  = {};
    @track localFiles = [];

    @track templateOptions = [];
    @track templateMap = {};


    // ── Lifecycle ────────────────────────────────────────
    connectedCallback() {
        this.localData  = { ...this.composeData };
        this.loadTemplates();
        this.localFiles = this.fileUpload ? [...this.fileUpload] : [];
    }

    loadTemplates() {
        getEmailTemplates()
            .then(data => {
                this.templateOptions = data.map(t => ({
                    label: t.name,
                    value: t.id
                }));

                // Store full template for later use
                data.forEach(t => {
                    this.templateMap[t.id] = t;
                });
            })
            .catch(error => {
                console.error('Error fetching templates', error);
            });
    }

    handleTemplateChange(event) {
        const templateId = event.target.value;

        if (!templateId) return;

        getTemplateBody({ templateId: templateId })
            .then(body => {

                const editor = this.template.querySelector('.editor');

                if (editor) {
                    // ✅ Clear existing content
                    editor.innerHTML = '';

                    // ✅ Insert template (IMPORTANT: no <p> if HTML)
                    editor.innerHTML = body || '';
                }

                // ✅ Sync with localData (VERY IMPORTANT)
                this.localData = { ...this.localData, body: body || '' };

                // ✅ Notify parent
                this.dispatchEvent(new CustomEvent('inputchange', {
                    detail: { field: 'body', value: body || '' }
                }));

                // ✅ Reset dropdown
                event.target.value = '';
            })
            .catch(error => {
                console.error('Error fetching template', error);
            });
    }

    renderedCallback() {
        // If parent already had body content, pre-fill the editor
        if (this.localData.body && !this._editorInitialized) {
            const editor = this.template.querySelector('.editor');
            if (editor) {
                editor.innerHTML = this.localData.body;
                this._editorInitialized = true;
            }
        }
    }

    // ── Editor helpers ───────────────────────────────────
    getEditor() {
        return this.template.querySelector('.editor');
    }

    exec(command, value = null) {
        this.getEditor().focus();
        document.execCommand(command, false, value);
    }

    // ── Toolbar actions ──────────────────────────────────
    bold()        { this.exec('bold'); }
    italic()      { this.exec('italic'); }
    underline()   { this.exec('underline'); }
    strike()      { this.exec('strikeThrough'); }
    alignLeft()   { this.exec('justifyLeft'); }
    alignCenter() { this.exec('justifyCenter'); }
    alignRight()  { this.exec('justifyRight'); }
    clearFormat() { this.exec('removeFormat'); }

    setFontSize(evt) {
        this.exec('fontSize', evt.target.value);
    }

    addLink() {
        const url = prompt('Enter URL:');
        if (url) this.exec('createLink', url);
    }

    uploadImage(evt) {
        const file = evt.target.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = (e) => {
            this.exec('insertImage', e.target.result);
        };
        reader.readAsDataURL(file);
    }

    // ── Body input ───────────────────────────────────────
    handleBodyInput(evt) {
        const value = evt.target.innerHTML;
        this.localData = { ...this.localData, body: value };
        this.dispatchEvent(new CustomEvent('inputchange', {
            detail: { field: 'body', value }
        }));
    }

    // ── Field inputs (To, CC, BCC, Subject) ─────────────
    handleInput(evt) {
        const field = evt.target.dataset.field;
        const value = evt.target.value;
        this.localData = { ...this.localData, [field]: value };
        this.dispatchEvent(new CustomEvent('inputchange', {
            detail: { field, value }
        }));
    }

    // ── File handling ─────────────────────────────────────
    handleFileChange(evt) {
        const newFiles = Array.from(evt.target.files).map(f => ({
            name: f.name,
            file: f,
            icon: f.type.includes('image') ? 'doctype:image'
                : f.type.includes('pdf')   ? 'doctype:pdf'
                : 'doctype:unknown'
        }));
        const merged = [...this.localFiles, ...newFiles].slice(0, 5);
        this.localFiles = merged;
        this.dispatchEvent(new CustomEvent('filechange', { detail: { files: merged } }));
    }

    handleRemoveFile(evt) {
        const index = parseInt(evt.currentTarget.dataset.index, 10);
        const updated = [...this.localFiles];
        updated.splice(index, 1);
        this.localFiles = updated;
        this.dispatchEvent(new CustomEvent('removefile', { detail: { index } }));
    }

    // ── Send / Close ──────────────────────────────────────
    handleSend() {
        this.dispatchEvent(new CustomEvent('send', {
            detail: { data: this.localData, files: this.localFiles }
        }));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}