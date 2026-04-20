import { LightningElement, track, api, wire } from 'lwc';
import getThreads from '@salesforce/apex/EmailInboxService.getThreads';
import sendEmail from '@salesforce/apex/EmailInboxService.sendEmail';
import getSentThreads from '@salesforce/apex/EmailInboxService.getSentThreads';
import getThreadMessages from '@salesforce/apex/EmailInboxService.getThreadMessages';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import sendReplyEmail from '@salesforce/apex/EmailInboxService.sendReplyEmail';
import deleteThread from '@salesforce/apex/EmailInboxService.deleteMessage';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { NavigationMixin } from 'lightning/navigation';
import generateReply from '@salesforce/apex/EmailOpenAIService.generateReply';
import getEmailTemplates from '@salesforce/apex/EmailTemplateController.getEmailTemplates';
import getTemplateBody from '@salesforce/apex/EmailTemplateController.getTemplateBody';
import getActiveRules from '@salesforce/apex/ArchiveRuleService.getActiveRules';
import saveRules from '@salesforce/apex/ArchiveRuleService.saveRules';
import removeFilter from '@salesforce/apex/CustomMetadataDeleter.deleteArchiveRules';

export default class EmailInbox extends NavigationMixin(LightningElement) {

    ChannelName = '/event/New_Email__e';
    ChannelChannelSubscription;

    allEmails = [];
    emails = [];
    selectedEmail;
    selectedId;
    showCompose = false;
    composeData = {
        to: '',
        cc: '',
        bcc: '',
        subject: '',
        body: ''
    };
    @track replyBoxVisible = false;
    replyData = {
        to: '',
        cc: '',
        subject: '',
        body: '',
        threadId: '',
        parentMessageId: ''
    };

    files = [];
    activeTab = 'inbox';
    @track templateOptions = [];
    @track templateMap = {};

    connectedCallback() {
        this.loadThreads();
        this.loadTemplates();
        this.subscribeToEvent();
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

        if (!templateId || !this.activeReplyId) return;

        getTemplateBody({ templateId: templateId })
            .then(body => {

                // 🔥 Find correct reply editor
                const editor = this.template.querySelector(
                    `.reply-box[data-id="${this.activeReplyId}"] .editor`
                );

                if (editor) {
                    // ✅ Step 1: Clear existing content
                    editor.innerHTML = '';

                    // ✅ Step 2: Insert template
                    if (body) {
                        editor.innerHTML = `<p>${body}</p>`;
                    }
                }

                // ✅ Reset dropdown
                event.target.value = '';
            })
            .catch(error => {
                console.error('Error fetching template', error);
            });
    }

  

    get inboxClass() {
        return this.activeTab === 'inbox' ? 'menu active' : 'menu';
    }

    get sentClass() {
        return this.activeTab === 'sent' ? 'menu active' : 'menu';
    }

    get trashClass() {
        return this.activeTab === 'trash' ? 'menu active' : 'menu';
    }

    get archiveClass() {
        return this.activeTab === 'archive' ? 'menu active' : 'menu';
    }

    @track emailStatus = '';
    @track emailTypApex = 'unarchived';

    handleMenuClick(event) {
        const tab = event.currentTarget.dataset.tab;
        this.activeTab = tab;

        this.emails = [];
        this.selectedEmail = null;
        this.emailOffset = 0;
        this.allEmails = [];

        if (tab === 'inbox') {
            this.emailStatus = '';
            this.emailTypApex = 'unarchived';
            this.loadThreads().then(() => {
                this.allEmails = [...this.emails];
            });

        } else if (tab === 'sent') {
            this.emailStatus = 'Active';        // ✅ set BEFORE call
            this.loadSentEmails().then(() => {
                this.allEmails = [...this.emails];
            });

        } else if (tab === 'trash') {
            this.emailStatus = 'Deleted';       // ✅ set BEFORE call
            this.loadSentEmails().then(() => {
                this.allEmails = [...this.emails];
            });
        }

        else if (tab === 'archive') {
            this.emailStatus = '';
            this.emailTypApex = 'archived';
            this.loadThreads().then(() => {
                this.allEmails = [...this.emails];
            });
        }
    }


    @track selectedViewAs = '00590000001DDBbAAO';
    @track avatarColor = '#6366f1';

    // Random colors pool
    avatarColors = [
        '#6366f1', '#ec4899', '#f59e0b', '#10b981',
        '#3b82f6', '#ef4444', '#8b5cf6', '#14b8a6',
        '#f97316', '#06b6d4'
    ];

    viewAsOptions = [
        { value: 'John Doe', label: 'John Doe' },
        { value: '00590000001DDBbAAO', label: 'Cloud Expert' },
        { value: '00590000002HXJNAA4', label: 'Shreyash' },
    ];

    get avatarInitial() {
        const match = this.viewAsOptions.find(o => o.value === this.selectedViewAs);
        return match ? match.label.charAt(0).toUpperCase() : 'U';
    }

    get avatarStyle() {
        return `background-color: ${this.avatarColor};`;
    }

    get avatarName() {
        const match = this.viewAsOptions.find(o => o.value === this.selectedViewAs);
        return match ? match.label : '';
    }

    handleAvatarClick(event) {
        event.stopPropagation();
        const others = this.avatarColors.filter(c => c !== this.avatarColor);
        this.avatarColor = others[Math.floor(Math.random() * others.length)];
    }

    handleViewAsChange(event) {
        this.selectedViewAs = event.target.value;

        console.log('Selected View >> ' + this.selectedViewAs);

        this.avatarColor = this.avatarColors[
            Math.floor(Math.random() * this.avatarColors.length)
        ];

        // ✅ Reset before loading new user's threads
        this.activeTab = 'inbox';
        this.emailStatus = '';
        this.emailOffset = 0;
        this.emails = [];
        this.allEmails = [];
        this.selectedEmail = null;
        this.threadMessages = {};
        this.threadOffsets = {};

        this.loadThreads();
    }




    get isTrashTab() {
        return this.activeTab === 'trash';
    }


    loadSentEmails() {
        console.log('Status >> ' + this.emailStatus);
        return new Promise((resolve, reject) => {   // ✅ return Promise
            getSentThreads({ emailStatus: this.emailStatus, viewAs: this.selectedViewAs })
                .then(data => {
                    this.allEmails = data.map(thread => {
                        const messages = thread.messages || [];
                        const lastMsg = messages[messages.length - 1];

                        return {
                            id: thread.threadId,
                            name: lastMsg ? lastMsg.toAddress : 'Unknown',
                            initial: lastMsg ? lastMsg.toAddress?.charAt(0).toUpperCase() : 'U',
                            subject: thread.subject,
                            preview: lastMsg?.body 
                                ? this.getPlainText(lastMsg.body).substring(0, 40) 
                                : '',
                            time: lastMsg ? this.formatTime(lastMsg.emailDate) : '',
                            unread: false,
                            className: `mail-card ${thread.threadId === this.selectedId ? 'active' : ''}`,
                            thread: messages.map(msg => ({
                                sender: msg.sender,
                                time: this.formatTime(msg.emailDate),
                                body: msg.body,
                                to: msg.toAddress,
                                cc: msg.ccAddress,
                                id: msg.messageId,
                                attachments: msg.attachments || []
                            }))
                        };
                    });

                    this.emails = [...this.allEmails];
                    resolve();  // ✅
                })
                .catch(error => {
                    console.error('Sent/Trash Error:', error);
                    reject(error);  // ✅
                });
        });
    }
    


    subscribeToEvent() {
        const messageCallback = (response) => {
            const payload = response.data.payload;
            console.log('Received new chat message: ', payload.MessageId__c);
            const currentThreadId = this.selectedEmail?.id;

            this.emailOffset = 0;
            this.emails = [];
            this.allEmails = [];

            this.loadThreads().then(() => {


                if (currentThreadId) {
                    const updated = this.emails.find(e => e.id === currentThreadId);

                    if (updated) {
                        this.selectedEmail = {
                            ...updated,
                            thread: this.threadMessages[currentThreadId] || []
                        };
                    } else {
                        this.selectedEmail = null;
                    }
                }

            });
            console.log('Apex refresh');
        };


        subscribe(this.ChannelName, -1, messageCallback)
            .then(response => {
                this.ChannelSubscription = response;
                console.log('Subscribed to channel:', this.ChannelName);
            }).catch(error => {
                console.error('Error subscribing to channel:', this.ChannelName, JSON.stringify(error));
            });
    }

    unsubscribeFromEvent() {
        if (this.ChannelSubscription) {
            unsubscribe(this.ChannelSubscription, response => {
                console.log('Unsubscribed from channel:', this.ChannelName);
            });
        }
    }

    /*  loadEmails() {
          getThreads()
              .then(data => {
  
                  this.allEmails = data.map(thread => {
  
                      const messages = thread.messages || [];
                      const lastMsg = messages[messages.length - 1];
  
                      return {
                          id: thread.threadId,
                          name: lastMsg ? lastMsg.sender : 'Unknown',
                          initial: lastMsg ? lastMsg.sender.charAt(0).toUpperCase() : 'U',
                          subject: thread.subject,
                          preview: (lastMsg && lastMsg.body)
                              ? String(lastMsg.body).substring(0, 40)
                              : '',
                          time: lastMsg ? this.formatTime(lastMsg.emailDate) : '',
                          unread: false,
  
                          className: `mail-card ${thread.threadId === this.selectedId ? 'active' : ''}`,
  
                          thread: messages.map(msg => ({
                              sender: msg.sender,
                              time: this.formatTime(msg.emailDate),
                              body: msg.body,
                              to: msg.toAddress,
                              cc: msg.ccAddress,
                              id: msg.messageId,
  
                              attachments: msg.attachments ? msg.attachments.map(file => {
                                  const isImage = ['png', 'jpg', 'jpeg', 'gif'].includes(
                                      (file.fileType || '').toLowerCase()
                                  );
  
                                  return {
                                      id: file.contentDocumentId,
                                      versionId: file.versionId,
                                      name: file.title + '.' + file.fileType,
                                      type: file.fileType,
                                      isImage: isImage,
  
                                      // ✅ THIS FIXES PREVIEW
                                      previewUrl: `/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=${file.versionId}`,
  
                                      // full preview (for iframe)
                                      fullUrl: `/sfc/servlet.shepherd/version/download/${file.versionId}`,
  
                                      showPreview: false
                                  };
                              }) : []
                          }))
                      };
                  });
  
                  this.emails = [...this.allEmails];
              })
              .catch(error => {
                  console.error('Error:', error);
              });
      }*/


    @track emails = [];
    @track threadMessages = {};
    @track selectedEmail = null;

    emailOffset = 0;
    threadOffsets = {};
    batchSize = 20;


    mapMessage(msg) {
        console.log(msg);
        return {
            id: msg.messageId,
            sender: msg.sender,
            body: msg.body,
            emailDate: msg.emailDate,
            time: this.formatTime(msg.emailDate),
            to: msg.toAddress,
            actualToAddress: msg.actualToAddress,
            cc: msg.ccAddress,
            isCase: msg.isCase === true || msg.isCase === 'true',
            isOpportunity: msg.isOpportunity === true || msg.isOpportunity === 'true',
            isOpportunityLinked: msg.isOpportunityLinked === true || msg.isOpportunityLinked === 'true',
            isTask: msg.isTask === true || msg.isTask === 'true',
            attachments: (msg.attachments || []).map(file => ({
                id: file.contentDocumentId,
                versionId: file.versionId,
                name: file.title + '.' + file.fileType,
                type: file.fileType,
                isImage: ['png', 'jpg', 'jpeg', 'gif'].includes((file.fileType || '').toLowerCase()),
                previewUrl: `/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=${file.versionId}`,
                fullUrl: `/sfc/servlet.shepherd/version/download/${file.versionId}`,
                showPreview: false
            })),
            isReplyOpen: false
        };
    }

    cleanHtml(html) {
        if (!html) return '';

        // Remove <style>...</style>
        html = html.replace(/<style[\s\S]*?>[\s\S]*?<\/style>/gi, '');

        // Remove <script>...</script> (safety)
        html = html.replace(/<script[\s\S]*?>[\s\S]*?<\/script>/gi, '');

        return html;
    }


    
    isLoadingThreads = false;
    isLoadingMessage = false;

    loadThreads() {
        if (this.isLoadingThreads) return; // ✅ block duplicate calls
        this.isLoadingThreads = true;

        return getThreads({ offsetSize: this.emailOffset, batchSize: this.batchSize, viewAs: this.selectedViewAs, emailType:this.emailTypApex })
            .then(data => {
                const threads = data.map(thread => {
                    const messages = thread.messages || [];
                    const lastMsg = messages[0];

                    return {
                        id: thread.threadId,
                        name: lastMsg ? lastMsg.sender : 'Unknown',
                        initial: lastMsg ? lastMsg.sender.charAt(0).toUpperCase() : 'U',
                        subject: thread.subject,
                        preview: lastMsg?.body 
                            ? this.getPlainText(lastMsg.body).substring(0, 40) 
                            : '',
                        time: lastMsg ? this.formatTime(lastMsg.emailDate) : '',
                        unread: false,
                        className: `mail-card ${thread.threadId === this.selectedId ? 'active' : ''}`,
                        thread: messages.map(msg => this.mapMessage(msg))
                    };
                });

                const existingIds = new Set(this.emails.map(e => e.id));
                const newThreads = threads.filter(t => !existingIds.has(t.id));

                this.emails = [...this.emails, ...newThreads];

                if (this.activeTab === 'inbox') {
                    this.allEmails = [...this.emails];
                }

                this.emailOffset += this.batchSize;
            })
            .catch(err => console.error(err))
            .finally(() => {
                this.isLoadingThreads = false;
            });
    }

    getPlainText(htmlString) {
        if (!htmlString) return '';

        const tempDiv = document.createElement('div');
        tempDiv.innerHTML = htmlString;
        return tempDiv.textContent || tempDiv.innerText || '';
    }


    

    loadMoreThreadMessages(threadId) {
        if (this.isLoadingMessage) return; 
        this.isLoadingMessage = true;

        if (!this.threadOffsets[threadId]) this.threadOffsets[threadId] = 0;

        const offset = this.threadOffsets[threadId];

        getThreadMessages({ threadId, offsetSize: offset, batchSize: this.batchSize, viewAs: this.selectedViewAs })
            .then(newMessages => {
                if (!this.threadMessages[threadId]) this.threadMessages[threadId] = [];

                const mapped = newMessages.map(msg => this.mapMessage(msg));

                const existingIds = new Set(this.threadMessages[threadId].map(m => m.id));
                const filteredMapped = mapped.filter(m => !existingIds.has(m.id));

                this.threadMessages[threadId] = [...this.threadMessages[threadId], ...filteredMapped];

                /* if (this.selectedEmail?.id === threadId) {
                     this.selectedEmail.thread = this.threadMessages[threadId];
                 }*/

                if (this.selectedEmail?.id === threadId) {
                    this.selectedEmail = {
                        ...this.selectedEmail,
                        thread: this.threadMessages[threadId].map(m => ({
                            ...m,
                            isReplyOpen: m.id === this.activeReplyId
                        }))
                    };
                }

                this.threadOffsets[threadId] += filteredMapped.length;
            })
            .catch(err => console.error(err))
            .finally(() => {
                this.isLoadingMessage = false;
            });
    }


    handleSelect(event) {
        const threadId = event.currentTarget.dataset.id;
        this.selectedId = threadId;


        this.emails = this.emails.map(mail => ({
            ...mail,
            unread: mail.id === threadId ? false : mail.unread,
            className: `mail-card ${mail.id === threadId ? 'active' : ''}`
        }));


        const sel = this.emails.find(mail => mail.id === threadId);
        this.selectedEmail = {
            ...sel,
            thread: this.threadMessages[threadId] || []
        };

        if (!this.threadMessages[threadId] || this.threadMessages[threadId].length === 0) {
            this.loadMoreThreadMessages(threadId);
        }
    }

    handleListScroll(event) {
        const el = event.target;
        if (el.scrollTop + el.clientHeight >= el.scrollHeight - 10) {
            this.loadThreads();
        }
    }


    handleThreadScroll(event) {
        const el = event.target;
        if (el.scrollTop + el.clientHeight >= el.scrollHeight - 10) {
            if (this.selectedEmail) {
                this.loadMoreThreadMessages(this.selectedEmail.id);
            }
        }
    }


    handleSearch(event) {
        const value = event.target.value.toLowerCase();
        const sourceEmails = this.allEmails || [];

        this.emails = sourceEmails.filter(mail =>
            (mail.name && mail.name.toLowerCase().includes(value)) ||
            (mail.subject && mail.subject.toLowerCase().includes(value))
        );
    }

    formatTime(dateStr) {
        if (!dateStr) return '';

        const date = new Date(dateStr);
        const now = new Date();

        const isToday =
            date.getDate() === now.getDate() &&
            date.getMonth() === now.getMonth() &&
            date.getFullYear() === now.getFullYear();

        if (isToday) {
            // Show time like "9:41 AM"
            return date.toLocaleTimeString([], {
                hour: 'numeric',
                minute: '2-digit',
                hour12: true
            });
        }

        const isThisYear = date.getFullYear() === now.getFullYear();

        if (isThisYear) {
            // Show like "Mar 28"
            return date.toLocaleDateString([], {
                month: 'short',
                day: 'numeric'
            });
        }

        // Older — show like "Mar 28, 2023"
        return date.toLocaleDateString([], {
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        });
    }

    handleInput(event) {
        const field = event.target.dataset.field;

        this.composeData = {
            ...this.composeData,
            [field]: event.target.value
        };
    }


    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }


    @track activeReplyId;
    handleReply(event) {
        const msgId = event.currentTarget.dataset.id;

        this.activeReplyId = msgId;

        const msg = this.selectedEmail.thread.find(m => m.id === msgId);

        this.replyData = {
            to: msg.to,
            cc: msg.cc || '',
            subject: 'Re: ' + this.selectedEmail.subject,
            body: '\n\n----------------------\n' + msg.body,
            threadId: this.selectedEmail.id,
            parentMessageId: msgId
        };

        // ✅ IMPORTANT: update UI state
        this.updateReplyState();

        setTimeout(() => {
            const target = this.template.querySelector(`.reply-box[data-id="${msgId}"]`);

            if (target) {
                // ✅ Step 1: Scroll
                target.scrollIntoView({
                    behavior: 'smooth',
                    block: 'center'
                });

                // ✅ Step 2: Wait for scroll to finish, then blink
                setTimeout(() => {
                    this.triggerBlink(target);
                }, 400); // 🔥 adjust (300–600ms based on UI)
            }
        }, 100);
    }


    triggerBlink(target) {
        target.style.transition = 'all 0.3s ease';

        // first flash
        target.style.backgroundColor = '#e0e7ff';
        target.style.border = '1px solid #4f46e5';

        setTimeout(() => {
            target.style.backgroundColor = '';
            target.style.border = '';

            // second flash
            setTimeout(() => {
                target.style.backgroundColor = '#e0e7ff';

                setTimeout(() => {
                    target.style.backgroundColor = '';
                }, 150);

            }, 100);

        }, 300);
    }



    updateReplyState() {
        this.selectedEmail = {
            ...this.selectedEmail,
            thread: this.selectedEmail.thread.map(m => {
                return {
                    ...m,
                    isReplyOpen: m.id === this.activeReplyId
                };
            })
        };
    }

    handleReplyInput(event) {
        const field = event.target.dataset.field;

        let value;

        // 🔥 handle contenteditable separately
        if (event.target.classList.contains('editor')) {
            value = event.target.innerHTML;   // ✅ get rich content
        } else {
            value = event.target.value;       // normal inputs
        }

        this.replyData = {
            ...this.replyData,
            [field]: value
        };

        console.log('Body:', this.replyData.body);
    }

    @track isSendingReply = false;

    sendReply() {   
        if (this.isSendingReply) return;

        this.isSendingReply = true;

        // 👇 Let UI update FIRST
        setTimeout(() => {

            const readerPromises = this.files.map(file => this.readFileAsync(file));

            Promise.all(readerPromises)
                .then(fileContents => {
                    return sendReplyEmail({
                        toAddress: this.replyData.to,
                        ccAddress: this.replyData.cc,
                        subject: this.replyData.subject,
                        body: this.replyData.body,
                        parentMessageId: this.activeReplyId,
                        fileNames: this.files.map(file => file.name),
                        fileContents: fileContents,
                        contType: this.files.map(file => file.type)
                    });
                })
                .then(() => {

                    this.activeReplyId = null;
                    this.replyData = {
                        to: '',
                        cc: '',
                        subject: '',
                        body: '',
                        threadId: '',
                        parentMessageId: ''
                    };

                    this.updateReplyState();

                    if (this.selectedEmail?.id) {
                        this.threadMessages[this.selectedEmail.id] = [];
                        this.threadOffsets[this.selectedEmail.id] = 0;
                        this.loadMoreThreadMessages(this.selectedEmail.id);
                    }

                    this.showToast('Success', 'Email sent successfully ✅', 'success');
                    this.fileUpload = [];
                    this.files = [];
                })
                .catch(error => {

                    console.error('Full Error:', JSON.stringify(error));

                    let message = 'Something went wrong';

                    if (error?.body?.message) {
                        message = error.body.message;
                    } else if (error?.body?.pageErrors?.length) {
                        message = error.body.pageErrors[0].message;
                    } else if (error?.message) {
                        message = error.message;
                    }

                    this.showToast('Error', message, 'error');
                })
                .finally(() => {
                    this.isSendingReply = false;
                });

        }, 0); // 👈 key trick





       /*sendReplyEmail({
            toAddress: this.replyData.to,
            ccAddress: this.replyData.cc,
            subject: this.replyData.subject,
            body: this.replyData.body,
            parentMessageId: this.activeReplyId
        })
            .then(() => {
                this.activeReplyId = null;
                this.replyData = {
                    to: '',
                    cc: '',
                    subject: '',
                    body: '',
                    threadId: '',
                    parentMessageId: ''
                };


                this.updateReplyState();


                if (this.selectedEmail?.id) {
                    this.threadMessages[this.selectedEmail.id] = [];
                    this.threadOffsets[this.selectedEmail.id] = 0;

                    this.loadMoreThreadMessages(this.selectedEmail.id);
                }

                this.showToast('Success', 'Email sent successfully ✅', 'success');

            })
            .catch(err => {
                console.error(err);
            });*/
    }

    handleReplyDelete() {
        this.activeReplyId = null;
        this.updateReplyState();
    }


    @track files = [];
    @track payMode = false;
    @track PaymentData;
    @track fileUpload = [];


    removeFile(event) {
        const fileIndex = event.target.dataset.index;
        this.files.splice(fileIndex, 1);
        this.fileUpload.splice(fileIndex, 1);
    }

    handleFileChange(event) {
        const newFiles = Array.from(event.target.files);
        const totalFiles = this.files.length + newFiles.length;

        if (totalFiles > 5) {
            alert("You can only select up to five files.");
            return;
        }
        else {
            this.files = [...this.files, ...newFiles];
            //   const newFiles = Array.from(event.target.files);
            this.fileUpload = [...this.fileUpload, ...newFiles.map(file => ({
                name: file.name,
                type: file.type,
                size: file.size,
                icon: this.getFileIcon(file.type)
            }))];
        }

    }

    getFileIcon(fileType) {
        const fileTypeIcons = {
            'image/jpeg': 'doctype:image',
            'image/png': 'doctype:image',
            'application/pdf': 'doctype:pdf',
            'application/msword': 'doctype:word',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'doctype:word',
            'application/vnd.ms-excel': 'doctype:excel',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'doctype:excel',
            'application/vnd.ms-powerpoint': 'doctype:ppt',
            'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'doctype:ppt',
            'text/plain': 'doctype:txt',
        };


        return fileTypeIcons[fileType] || 'doctype:attachment';
    }



    readFileAsync(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result.split(',')[1]);
            reader.onerror = error => reject(error);
            reader.readAsDataURL(file);
        });
    }


    handleSend() {

        if (!this.composeData.to) {
            this.showToast('Error', 'To address is required', 'error');
            return;
        }
        const readerPromises = this.files.map(file => this.readFileAsync(file));
        Promise.all(readerPromises)
            .then(fileContents => {
                sendEmail({
                    toAddress: this.composeData.to,
                    ccAddress: this.composeData.cc,
                    bccAddress: this.composeData.bcc,
                    subject: this.composeData.subject,
                    body: this.composeData.body,
                    fileNames: this.files.map(file => file.name),
                    fileContents: fileContents,
                    contType: this.files.map(file => file.type)
                })
                    .then(() => {
                        this.showToast('Success', 'Email sent successfully ✅', 'success');
                        this.showCompose = false;
                        this.composeData = {
                            to: '',
                            cc: '',
                            bcc: '',
                            subject: '',
                            body: ''
                        };

                        this.fileUpload = [];
                        
                    })
                    .catch(error => {

                        console.error('Full Error:', JSON.stringify(error));

                        let message = 'Something went wrong';

                        if (error?.body?.message) {
                            message = error.body.message;
                        } else if (error?.body?.pageErrors && error.body.pageErrors.length > 0) {
                            message = error.body.pageErrors[0].message;
                        } else if (error?.message) {
                            message = error.message;
                        }

                        this.showToast('Error', message, 'error');
                    });

            })
            .catch(error => {

            })
            .finally(() => {

            });
    }

    previewFile(event) {
        const fileId = event.currentTarget.dataset.id;

        this.selectedEmail = {
            ...this.selectedEmail,
            thread: this.selectedEmail.thread.map(msg => {
                return {
                    ...msg,
                    attachments: msg.attachments.map(file => {
                        return {
                            ...file,
                            showPreview: file.id === fileId ? !file.showPreview : false
                        };
                    })
                };
            })
        };
    }


    showFilepreviewFile(event) {
        const docId = event.currentTarget.dataset.id;

        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                selectedRecordId: docId
            }
        });
    }

    downloadFile(event) {
        const docId = event.currentTarget.dataset.id;

        window.open(
            `/sfc/servlet.shepherd/document/download/${docId}`,
            '_blank'
        );
    }

    @track defaultComposeData = {
        to: '',
        cc: '',
        bcc: '',
        subject: '',
        body: ''
    };

    closeCompose() {
        this.composeData = { ...this.defaultComposeData };
        this.fileUpload = [];
        this.isMinimized = false;
        this.showCompose = false;
    }

    formatBody(body) {
        if (!body) return '';

        const urlRegex = /(https?:\/\/[^\s]+)/g;

        let formatted = body
            .replace(/\n/g, '<br/>') // ✅ preserve line breaks
            .replace(urlRegex, (url) => {
                const safeUrl = encodeURI(url); // ✅ safety
                return `<a href="${safeUrl}" target="_blank">${safeUrl}</a>`;
            });

        return formatted;
    }

    @track value = '';

    handleInput(event) {
        this.value = event.target.innerHTML;
    }

    exec(cmd, value = null) {
        const editor = this.template.querySelector('.editor');

        if (editor) {
            editor.focus(); // 🔥 restore focus before command
            document.execCommand(cmd, false, value);
        }
    }

    bold() { this.exec('bold'); }
    italic() { this.exec('italic'); }
    underline() { this.exec('underline'); }
    strike() { this.exec('strikeThrough'); }

    unorderedList() {
        this.exec('insertUnorderedList');
    }

    orderedList() {
        this.exec('insertOrderedList');
    }

    indent() { this.exec('indent'); }
    outdent() { this.exec('outdent'); }

    alignLeft() { this.exec('justifyLeft'); }
    alignCenter() { this.exec('justifyCenter'); }
    alignRight() { this.exec('justifyRight'); }

    setFontSize(event) {
        this.exec('fontSize', event.target.value);
    }

    addLink() {
        const url = prompt('Enter URL');
        if (url) {
            this.exec('createLink', url);
        }
    }

    uploadImage(event) {
        const file = event.target.files[0];
        if (!file) return;

        const reader = new FileReader();
        reader.onload = () => {
            this.exec('insertImage', reader.result);
        };
        reader.readAsDataURL(file);
    }

    clearFormat() {
        this.exec('removeFormat');
    }

    preventBlur(event) {
        event.preventDefault(); // 🔥 stops focus from leaving editor
    }

    @track showPopup = false;
    @track selectedAction = '';
    @track emailId = '';

    handleAction(event) {
        const type = event.currentTarget.dataset.type;

        this.emailId = event.currentTarget.dataset.id;

        this.selectedAction = type;
        this.showPopup = true;
    }

    handleClosePopup() {
        this.showPopup = false;

        const threadId = this.selectedEmail?.id;

        if (threadId) {
            // ✅ Reset data
            this.threadMessages[threadId] = [];
            this.threadOffsets[threadId] = 0;

            // ✅ Reload fresh messages
            this.loadMoreThreadMessages(threadId);
        }
    }

    showOppBridgeModal = false;
    selectedEmailId;

    handleOppBridge(event) {
        const msgId = event.currentTarget.dataset.id;

        this.type = 'link';
        this.selectedEmailId = msgId;   // only message Id
        this.showOppBridgeModal = true; // open modal
    }

    handleCloseOppBridge() {
        this.showOppBridgeModal = false;
        const threadId = this.selectedEmail?.id;

        if (threadId) {
            // ✅ Reset data
            this.threadMessages[threadId] = [];
            this.threadOffsets[threadId] = 0;

            // ✅ Reload fresh messages
            this.loadMoreThreadMessages(threadId);
        }
    }


    handleShowLinkOpp(event) {
        const msgId = event.currentTarget.dataset.id;

        this.type = 'show';
        console.log('Email Body >> ' + msgId);

        this.selectedEmailId = msgId;
        this.showOppBridgeModal = true;
    }

    handleRefresh() {

        const threadId = this.selectedEmail?.id;

        if (threadId) {
            // ✅ Reset data
            this.threadMessages[threadId] = [];
            this.threadOffsets[threadId] = 0;

            // ✅ Reload fresh messages
            this.loadMoreThreadMessages(threadId);
        }

        const currentThreadId = this.selectedEmail?.id;

        this.emailOffset = 0;
        this.emails = [];
        this.allEmails = [];

        if (currentThreadId) {
            this.threadMessages[currentThreadId] = [];
            this.threadOffsets[currentThreadId] = 0;
        }


        this.loadThreads().then(() => {

            if (currentThreadId) {
                const updated = this.emails.find(e => e.id === currentThreadId);

                if (updated) {
                    this.selectedEmail = {
                        ...updated,
                        thread: []
                    };

                    this.loadMoreThreadMessages(currentThreadId);
                } else {
                    this.selectedEmail = null;
                }
            }

        });


    }



    handleDeleteEmail(event) {
        event.stopPropagation();
        const emailId = event.currentTarget.dataset.id;
        const currentThreadId = this.selectedEmail?.id;
        const action = event.currentTarget.dataset.action;

        console.log('Action >> ' + action);

        deleteThread({ threadId: emailId, actionType: action })
            .then(result => {
                if (result === 'success') {
                    // ✅ Full reset to prevent duplicates
                    this.emailOffset = 0;
                    this.emails = [];
                    this.allEmails = [];
                    this.threadMessages = {};
                    this.threadOffsets = {};
                    this.selectedEmail = null;

                    if (action === 'delete') {
                        // ✅ Check which tab user is on
                        if (this.activeTab === 'inbox') {
                            return this.loadThreads();
                        } else if (this.activeTab === 'sent') {
                            this.emailStatus = 'Active';
                            return this.loadSentEmails();
                        } else if (this.activeTab === 'trash') {
                            this.emailStatus = 'Deleted';
                            return this.loadSentEmails();
                        }
                    } else {
                        // undelete — always reload trash
                        this.emailStatus = 'Deleted';
                        return this.loadSentEmails();
                    }
                }
            })
            .then(() => {
                // ✅ Only try to re-select if thread still exists after reload
                if (currentThreadId) {
                    const updated = this.emails.find(e => e.id === currentThreadId);
                    this.selectedEmail = updated
                        ? { ...updated, thread: this.threadMessages[currentThreadId] || [] }
                        : null;
                }

                if (action === 'delete') {
                    this.showToast('Success', 'Email deleted successfully ✅', 'success');
                } else {
                    this.showToast('Success', 'Email Restored successfully ✅', 'success');
                }
            })
            .catch(error => {
                let message = 'Something went wrong';
                if (error?.body?.message) {
                    message = error.body.message;
                } else if (error?.body?.pageErrors?.length > 0) {
                    message = error.body.pageErrors[0].message;
                } else if (error?.message) {
                    message = error.message;
                }
                this.showToast('Error', message, 'error');
            });
    }


    // ── Minimize / Maximize state ──────────────────────────
    isMinimized = false;
    showMaximized = false;

    get composeModalClass() {
        return this.isMinimized ? 'compose-modal minimized' : 'compose-modal';
    }

    toggleMinimize() {
        this.isMinimized = !this.isMinimized;
    }

    openMaximized() {
        this.showMaximized = true;   // open big modal
        this.showCompose = false;  // hide small compose
        this.isMinimized = false;
    }

    handleMaximizedClose() {
        this.showMaximized = false;
        this.showCompose = true;   // restore small compose
    }

    handleMaximizedSend(evt) {
        // ✅ get data from child
        this.composeData = evt.detail.data;
        this.fileUpload  = evt.detail.files;

        // ✅ call your actual send logic
        this.handleSend();

        // optional UI handling
        this.showMaximized = false;
    }

    handleMaximizedInput(evt) {
        const { field, value } = evt.detail;
        this.composeData = { ...this.composeData, [field]: value };
    }

    handleMaximizedFileChange(evt) {
        this.fileUpload = evt.detail.files;
    }

    handleMaximizedRemoveFile(evt) {
        const index = evt.detail.index;
        const updated = [...this.fileUpload];
        updated.splice(index, 1);
        this.fileUpload = updated;
    }

    handleCompose() {
        this.isMinimized = false;
        this.showMaximized = false;
        this.showCompose = true;       
        this.composeData = { ...this.defaultComposeData };  
    }    

    showAIPanel = false;
    aiEmailId;
    isAnyAIProcessing = false;

    handleAISummarise(event) {        
        this.isAnyAIProcessing = true;
        this.aiEmailId = event.currentTarget.dataset.id;
        this.showAIPanel = true;

        setTimeout(() => {
            const cmp = this.template.querySelector('c-ai-summary-panel');
            if (cmp) {
                cmp.loadSummary();
            }
        }, 0);
    }

    handleSummaryDone() {
        this.isAnyAIProcessing = false; // ✅ re-enable buttons
    }

    handleAIPanelClose() {
        this.showAIPanel = false;
    }

    handleAIQuickAction(event) {
        this.selectedAction = event.detail.type;
        this.emailId = event.detail.emailId;
        this.showPopup = true;
    }
    
    
    handleAIReplyInEmail(event) {
        if (this.isAnyAIProcessing) return;
        const { emailId, aiReply } = event.detail;

        const msg = this.selectedEmail.thread.find(m => m.id === emailId);
        if (!msg) return;    
        
        this.activeReplyId = msg.id;

        console.log('Body >> ' + aiReply);


        this.replyData = {
            to: msg.actualToAddress,
            cc: msg.cc || '',
            subject: 'Re: ' + this.selectedEmail.subject,
            body: aiReply,
            threadId: this.selectedEmail.id,
            parentMessageId: msg.id
        };

        this.updateReplyState();

        Promise.resolve().then(() => {
            this.populateReplyEditor(this.replyData.body);

            setTimeout(() => {
                const target = this.template.querySelector(`.reply-box[data-id="${msg.id}"]`);
                if (target) {
                    target.scrollIntoView({ behavior: 'smooth', block: 'center' });
                    setTimeout(() => this.triggerBlink(target), 400);
                }
            }, 100);
        });
    }

     populateReplyEditor(content) {
        // ✅ AI returns HTML directly — no escaping needed
        this.replyData = { ...this.replyData, body: content };

        const replyBox = this.template.querySelector(`.reply-box[data-id="${this.activeReplyId}"]`);
        const editor = replyBox ? replyBox.querySelector('.editor') : null;

        if (editor) {
            editor.innerHTML = content;
        }
    }


    @track loadingText = 'Generating...'
    @track promptSend = 'Send';    
    selectedTone = 'professional'; // default

    get toneOptions() {
        return [
            { value: 'professional', label: 'Professional' },
            { value: 'casual',       label: 'Casual'       },
            { value: 'formal',       label: 'Formal'       }
        ].map(t => ({
            ...t,
            cssClass: `tone-btn ${this.selectedTone === t.value ? 'tone-btn--active' : ''}`
        }));
    }

    handleToneChange(event) {
        this.selectedTone = event.currentTarget.dataset.tone;
    }

    handleAIReply(event){
        if (this.isAnyAIProcessing) return;
        this.isAnyAIProcessing = true;
        this.emailId = event.currentTarget.dataset.id; 
        console.log('Email Id >> ' + this.emailId);   

        this.promptSend = 'Generating...'

        generateReply({ emailId: this.emailId, userPrompt: this.promptText, tone : this.selectedTone  })
            .then(result => {

                console.log('AI Reply:', result);
                
                const msg = this.selectedEmail.thread.find(m => m.id === this.emailId);
                if (!msg) return;    
                
                this.activeReplyId = msg.id;    

                this.replyData = {
                    to: msg.actualToAddress,
                    cc: msg.cc || '',
                    subject: 'Re: ' + this.selectedEmail.subject,
                    body: result,
                    threadId: this.selectedEmail.id,
                    parentMessageId: msg.id
                };

                this.updateReplyState();

                Promise.resolve().then(() => {
                    this.populateReplyEditor(this.replyData.body);

                    setTimeout(() => {
                        const target = this.template.querySelector(`.reply-box[data-id="${msg.id}"]`);
                        if (target) {
                            target.scrollIntoView({ behavior: 'smooth', block: 'center' });
                            setTimeout(() => this.triggerBlink(target), 400);
                        }
                    }, 100);
                });

                if(this.showPromptModal){
                    this.showPromptModal = false;
                }
        })
        .catch(error => {
                console.error('Reply Error:', error);               
                
        })
        .finally(() => {
            this.isAnyAIProcessing = false; 
            this.promptSend = 'Send';
        });
    }

    
   /* handleAIReply(event) {

        if (this.isAnyAIProcessing) return;

        this.isAnyAIProcessing = true;
        this.loadingText = 'Thinking...';

        // simulate API delay (3 seconds)
        setTimeout(() => {
            this.isAnyAIProcessing = false;
        }, 3000);
    }*/

    @track showPromptModal = false;
    handleAIPromptReply(event) {
       // if (this.isAnyAIProcessing) return;
        this.emailId = event.currentTarget.dataset.id;
        this.promptText = '';
        this.showPromptModal = true;
        
    }

    handlePromptChange(event) {
        this.promptText = event.target.value;
    }

    handleClosePrompt(){
        this.showPromptModal = false;
    }   


    // STATE
    @track showArchiveModal = false;
    @track managerules = [];
    @track rules = [];
    @track ruleType = 'email';
    @track ruleValue = '';

    matchType = 'sender';
    @track isLoadingRules = false;

   

    get isSaveDisabled() {
        return !this.rules || this.rules.length === 0;
    }

    // INPUT HANDLING
    handleRuleType(event) {
        this.ruleType = event.target.value;
    }

    handleRuleValue(event) {
        this.ruleValue = event.target.value;
    }

    addRule() {
        if (!this.ruleValue) return;

        const labelMap = {
            email: 'Email',
            keyword: 'Keyword',
            domain: 'Domain'
        };

        const classMap = {
            email: 'archive-badge email',
            keyword: 'archive-badge keyword',
            domain: 'archive-badge domain'
        };

        this.rules = [
            ...this.rules,
            {
                id: Date.now(),
                type: this.ruleType,
                label: labelMap[this.ruleType],
                value: this.ruleValue,
                badgeClass: classMap[this.ruleType] // ✅ important
            }
        ];

        this.ruleValue = '';
    }

    // REMOVE RULE
   

    // MATCH TYPE
    handleMatch(event) {
        this.matchType = event.target.value;
    }

    activeTabRule = 'add';
    closeArchiveModal() {
        this.showArchiveModal = false;
        this.rules = [];
        this.managerules = [];
        this.activeTabRule = 'add';
    }

    get isAddTab() {
        return this.activeTabRule === 'add';
    }

    get isManageTab() {
        return this.activeTabRule === 'manage';
    }

    handleTabChange(event) {
        this.activeTabRule = event.target.dataset.tab;
    }

    get addTabClass() {
        return this.activeTabRule === 'add'
            ? 'archive-tab active'
            : 'archive-tab';
    }

    get manageTabClass() {
        return this.activeTabRule === 'manage'
            ? 'archive-tab active'
            : 'archive-tab';
    }

    openArchiveModal() {
        this.showArchiveModal = true;
        this.isLoadingRules = false;
        this.managerules = [];
        getActiveRules()
            .then(data => {
                console.log('Rules Data:', data);

                if (!data || data.length === 0) {
                    this.managerules = [];
                    return;
                }

                this.managerules = data.map(rule => {
                    const typeVal   = rule?.Rule_Type__c || '';
                    const valueVal  = rule?.Rule_Value__c || '';
                    const lowerType = typeVal ? typeVal.toLowerCase() : '';
                    const apiname = rule.DeveloperName;
                    
                    return {
                        id: Date.now() + Math.random(),
                        type: lowerType,
                        label: typeVal || 'Unknown',
                        value: valueVal || '',
                        developername : apiname,
                        badgeClass: lowerType ? `archive-badge ${lowerType}` : 'archive-badge'
                    };
                });
            })
            .catch(err => {
                console.error('Error:', err);
                this.isLoadingRules = true;
                this.showToast(
                    'Error',
                    err?.body?.message || 'Failed to load rules',
                    'error'
                );
            })
            .finally(() => {
                this.isLoadingRules = false;
            });
    }

    removeRule(event) {
        this.isLoadingRules = true;

        const index = event.currentTarget.dataset.index;
        this.managerules.splice(index, 1);
       

        const apiName = event.currentTarget.dataset.developername;
        console.log('Removing... >> ' + apiName)

       
        removeFilter({developerName : apiName })
        .then(() => {
            this.showToast('Success', 'Rules saved successfully', 'success');
            this.managerules = [...this.managerules];              
        })
        .catch(error => {
            console.error(error);
             this.isLoadingRules = false;
            this.showToast('Error', error.body.message, 'error');
        })
        .finally(() => {
            this.isLoadingRules = false;
        });
    }
    

    removeBeforeRule(event) {
        this.isLoadingRules = true;
        const index = event.currentTarget.dataset.index;
        this.rules.splice(index, 1);       
        this.rules = [...this.rules];  
            
    }

    handleUnarchived(){
        this.closeArchiveModal();
        this.handleRefresh();
    }
    

    saveRules() {
        
        if (!this.rules || this.rules.length === 0) {
            this.showToast('Error', 'Please add at least one rule before saving.', 'error');
            return;
        }

        const payload = this.rules.map(r => {
            const uniqueName = 'Rule_' + Math.random().toString(36).substring(2, 10).toUpperCase();

            return {
                rType: String(r.type),     // 🔥 force primitive
                rValue: String(r.value),
                label: String(r.label || (r.type + ' ' + r.value)),
                uniqueName: uniqueName
            };
        });

        // 🔥 THIS LINE IS KEY
        const cleanPayload = JSON.parse(JSON.stringify(payload));

        console.log('Payload:', cleanPayload);

        saveRules({
            rules: cleanPayload,
            matchType: this.matchType
        })
        .then(() => {
            this.showToast('Success', 'Rules saved successfully', 'success');
            this.closeArchiveModal();

            // 🔥 IMPORTANT: Refresh inbox with new rules applied
           // this.refreshInboxAfterRuleSave();
           this.refreshInboxAfterRuleSave();
        })
        .catch(error => {
            console.error(error);
            this.showToast('Error', 'Failed to save rules', 'error');
        });
    }

    handleCheckEvent(event){

        const action = event.currentTarget.dataset.event;

        if(save === 'save'){
            this.saveRules();
        }
    }

    refreshAll(){
        this.activeTab = 'inbox';
        this.emailStatus = 'unarchived';
        this.emailOffset = 0;
        this.emails = [];
        this.allEmails = [];
        this.selectedEmail = null;
        this.threadMessages = {};
        this.threadOffsets = {};

        this.loadThreads();
    }

    refreshInboxAfterRuleSave() {
        const currentThreadId = this.selectedEmail?.id;
        
        this.emailOffset = 0;
        this.emails = [];
        this.allEmails = [];
        this.threadMessages = {};
        this.threadOffsets = {};
        this.selectedEmail = null;

        
        if (this.activeTab === 'inbox') {

            this.loadThreads().then(() => {

                if (currentThreadId) {
                    const updated = this.emails.find(e => e.id === currentThreadId);

                    if (updated) {
                        this.selectedEmail = {
                            ...updated,
                            thread: []
                        };

                        this.loadMoreThreadMessages(currentThreadId);
                    }
                }
            });

        } else if (this.activeTab === 'sent') {

            this.emailStatus = 'Active';
            this.loadSentEmails();

        } else if (this.activeTab === 'trash') {

            this.emailStatus = 'Deleted';
            this.loadSentEmails();

        } else if (this.activeTab === 'archive') {

            this.loadSentEmails();
        }
    }
    

}