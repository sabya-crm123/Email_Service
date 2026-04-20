import { LightningElement, api, wire, track } from 'lwc';
import caseInsertReco from '@salesforce/apex/emailActionController.saveCase';
import taskUpdate from '@salesforce/apex/emailActionController.saveTask';
import oppInsertReco from '@salesforce/apex/emailActionController.saveOpportunity';
import getDetails from '@salesforce/apex/emailActionController.getEmailDetails';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ActionPopup extends LightningElement {
    
    @api isOpen = false;
    @track showSpinner = true;
     @track showModalSpinner = false;
    @api actionType = '';
    @api emailId = '';

    connectedCallback() {       
        console.log('Email Id >> ' + this.emailId);
        console.log('Action Id >> ' + this.emailId);
    }
    
    get isCase() {
        return this.actionType === 'Case';
    }

    get isOpportunity() {
        return this.actionType === 'Opportunity';
    }

    get isTask() {
        return this.actionType === 'Task';
    }

    get headerLabel() {
        return this.actionType + ' Action';
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    @track caseVariable = {
        Subject : '', Description : null, Origin : 'Email', Priority:'Medium', AccountId : null, ContactId : null, Project1__c : null
    };


    wireServiceResponse;

    @wire(getDetails, { emailId: '$emailId' })
    async on_callback(response) {
        this.showSpinner = true; 
        refreshApex(response)
        console.log("Response is" + response);

        this.wireServiceResponse = response;
        let data = response.data;
        let error = response.error;

       if (data) {   
            this.caseVariable = {
                ...this.caseVariable,
                Subject: data?.subject || '',
                Description: data?.body ? this.stripHtml(data.body) : '',
                AccountId: data?.accountId || null,
                ContactId: data?.contactId || null,
                Project1__c: data?.projectId || null,
                Contact_2__c: data?.owner || null
            };

            this.oppVariable = {
                ...this.caseVariable,
                AccountId: data?.accountId || null,
                Key_Contact__c: data?.contactId || null,
                Description: data?.subject || ''
            };

            this.taskVariable = {
                ...this.taskVariable,
                Subject: data?.subject || '',
                Description: data?.body ? this.getTrimmedText(data.body) : ''
            };

            this.showSpinner = false;
        }
        if (error) {
            let errorMessage = error.body.message;
            this.showErrorToast(errorMessage);
            this.showSpinner = false;
        }
    }


    stripHtml(html) {
        if (!html) return '';

        // Create temporary DOM element
        const tempDiv = document.createElement('div');
        tempDiv.innerHTML = html;

        // Return only text
        return tempDiv.textContent || tempDiv.innerText || '';
    }

    getTrimmedText(html) {
        if (!html) return '';

        // Remove HTML
        const tempDiv = document.createElement('div');
        tempDiv.innerHTML = html;

        let text = tempDiv.textContent || tempDiv.innerText || '';

        // Clean spaces
        text = text.replace(/\s+/g, ' ').trim();

        // Limit to 255 characters
        return text.length > 255 ? text.substring(0, 255) : text;
    }


    handleCaseField(event){
        let fieldName = event.target.fieldName || event.target.dataset.field; 
        let fieldValue = event.target.value;

        this.caseVariable = {
            ...this.caseVariable,
            [fieldName]: fieldValue
        };

       
    }

     @track oppVariable = {
        Name:'',
        CloseDate : this.getTodayDate(),
        StageName : 'Propsecting',
        AccountId : null,
        Key_Contact__c : null,
        LeadSource: 'Email',
        Description : null,
        Service_Interested__c : 'CRM'
    };

    handleOppField(event){
        let fieldName = event.target.fieldName || event.target.dataset.field; 
        let fieldValue = event.target.value;

        this.oppVariable = {
            ...this.oppVariable,
            [fieldName]: fieldValue
        };

       
    }

    getTodayDate() {
        const today = new Date();
        const yyyy = today.getFullYear();
        let mm = today.getMonth() + 1; // Months start at 0
        let dd = today.getDate();

        // Add leading zero if needed
        if (dd < 10) dd = '0' + dd;
        if (mm < 10) mm = '0' + mm;

        return `${yyyy}-${mm}-${dd}`; // format: yyyy-mm-dd
    }

    @track taskVariable = {
        Subject : '',
        Comment : '',
        ActivityDate : this.getTodayDate(),
        Priority : 'High',
        Status : 'Not Started'
     };

    @track showfield = false;

    handleTaskField(event) {
        const field = event.target.dataset.field;  
        const value = event.target.value;          

        this.taskVariable = { 
            ...this.taskVariable, 
            [field]: value 
        };

       
    }

    handleCase(){
        console.log(JSON.stringify(this.caseVariable));
        this.showSpinner = true;

         caseInsertReco({ caseJson: JSON.stringify(this.caseVariable), emailId : this.emailId})
            .then(result => {
                console.log('Apex returned:', result);

                this.showSuccessToast('Case Created Successfully');
                this.caseVariable = {
                    Subject : '', Description : null, Origin : 'Email', Priority:'Medium', AccountId : null, ContactId : null, Project1__c : null
                };
                this.handleClose();
                
            })
            .catch(error => {
                console.error('Error updating account:', error);
                this.showErrorToast(error.body.message);
                this.showSpinner = false;
            })
            .finally(() => {
                this.handleClose();
                this.showSpinner = false;
                this.caseVariable = {
                    Subject : '', Description : null, Origin : 'Email', Priority:'Medium', AccountId : null, ContactId : null, Project1__c : null
                };
            });
    }

    handleTask(){
        console.log(JSON.stringify(this.taskVariable));
        this.showSpinner = true;

        taskUpdate({ taskJson: JSON.stringify(this.taskVariable), emailId : this.emailId})
            .then(result => {
                console.log('Apex returned:', result);

                this.showSuccessToast('Task Created Successfully');
                this.handleClose();
                this.taskVariable = {
                    Subject : '',
                    Comment : '',
                    ActivityDate : this.getTodayDate(),
                    Priority : 'High',
                    Status : 'Not Started'
                };
                
            })

            .catch(error => {
                console.error('Error updating account:', error);
                this.showErrorToast(error.body.message);
                this.showSpinner = false;
            })
            .finally(() => {
                this.handleClose();
                this.showSpinner = false;
                this.formData = {
                    Subject : '',
                    Comment : '',
                    ActivityDate : this.getTodayDate(),
                    Priority : 'High',
                    Status : 'Not Started'
                };
            });
    }


     showSuccessToast(message) {
        const event = new ShowToastEvent({
            title: 'Success',
            message: message,
            variant: 'success',
            mode: 'dismissable'
        });
        this.dispatchEvent(event);
    }

    
    showErrorToast(message) {
        const event = new ShowToastEvent({
            title: 'Error',
            message: message,
            variant: 'error',
            mode: 'dismissable'
        });
        this.dispatchEvent(event);
    }


    handleOpportunity(){
        this.showSpinner = true;
         oppInsertReco({ oppJson: JSON.stringify(this.oppVariable),  emailId : this.emailId})
            .then(result => {
                console.log('Apex returned:', result);

                this.showSuccessToast('Opportunity Created Successfully');
                 this.oppVariable = {
                    Name:'',
                    CloseDate : this.getTodayDate(),
                    StageName : 'Propsecting',
                    AccountId : null,
                    Key_Contact__c : null,
                    LeadSource: 'Email',
                    Description : null,
                    Service_Interested__c : 'CRM'
                };
                this.handleClose();
            })

            .catch(error => {
                console.error('Error updating account:', error);
                this.showErrorToast(error.body.message);
                this.showSpinner = false;
            })
            .finally(() => {
                this.handleClose();
                this.showSpinner = false;
                this.oppVariable = {
                    Name:'',
                    CloseDate : this.getTodayDate(),
                    StageName : 'Propsecting',
                    AccountId : null,
                    Key_Contact__c : null,
                    LeadSource: 'Email',
                    Description : null,
                    Service_Interested__c : 'CRM'
                };

            });
    }


    get priorityOptions() {
        return [
            { label: 'High', value: 'High' },
            { label: 'Normal', value: 'Normal' },
            { label: 'Low', value: 'Low' }
        ];
    }

    get statusOptions() {
        return [
            { label: 'Not Started', value: 'Not Started' },
            { label: 'Completed', value: 'Completed' }
        ];
    }


}