// createOpportunity.js
import { LightningElement, track } from 'lwc';
import { createRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getStageNames from '@salesforce/apex/OpportunityController.getStageNames';
import OPPORTUNITY_OBJECT from '@salesforce/schema/Opportunity';
import NAME_FIELD from '@salesforce/schema/Opportunity.Name';
import STAGE_FIELD from '@salesforce/schema/Opportunity.StageName';
import DATE_FIELD from '@salesforce/schema/Opportunity.CloseDate';

export default class CreateOpportunity extends LightningElement {
    @track oppName = '';
    @track stage = '';
    @track closeDate = '';
    @track stageOptions;

    connectedCallback() {
        this.fetchStageNames();
    }

    fetchStageNames() {
        getStageNames()
            .then(result => {
                this.stageOptions = result.map(stage => {
                    return { label: stage, value: stage };
                });
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error loading stage names',
                        message: error.body.message,
                        variant: 'error'
                    })
                );
            });
    }

    handleNameChange(event) {
        this.oppName = event.target.value;
    }

    handleStageChange(event) {
        this.stage = event.detail.value;
    }

    handleDateChange(event) {
        this.closeDate = event.target.value;
    }

    createOpportunity() {
        const fields = {};
        fields[NAME_FIELD.fieldApiName] = this.oppName;
        fields[STAGE_FIELD.fieldApiName] = this.stage;
        fields[DATE_FIELD.fieldApiName] = this.closeDate;

        const recordInput = { apiName: OPPORTUNITY_OBJECT.objectApiName, fields };

        createRecord(recordInput)
            .then(opportunity => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Opportunity created',
                        variant: 'success'
                    })
                );
                // Navigate to the created opportunity record
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: opportunity.id,
                        objectApiName: 'Opportunity',
                        actionName: 'view'
                    }
                });
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error creating record',
                        message: error.body.message,
                        variant: 'error'
                    })
                );
            });
    }
}
