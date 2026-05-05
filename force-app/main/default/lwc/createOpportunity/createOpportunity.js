// createOpportunity.js
// Lightweight form to create an Opportunity. The previous version swallowed
// the .catch silently — fixed to show a toast on success or failure.
import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createOpportunityRecord
    from '@salesforce/apex/OpportunityController.createOpportunity';

export default class CreateOpportunity extends LightningElement {
    @track oppName = '';
    @track oppCloseDate = '';
    @track oppStage = '';

    stageOptions = [
        { label: 'Prospecting', value: 'Prospecting' },
        { label: 'Qualification', value: 'Qualification' },
        { label: 'Needs Analysis', value: 'Needs Analysis' },
        { label: 'Value Proposition', value: 'Value Proposition' },
        { label: 'Proposal/Price Quote', value: 'Proposal/Price Quote' },
        { label: 'Negotiation/Review', value: 'Negotiation/Review' },
        { label: 'Closed Won', value: 'Closed Won' },
        { label: 'Closed Lost', value: 'Closed Lost' }
    ];

    handleNameChange(event) { this.oppName = event.target.value; }
    handleCloseDateChange(event) { this.oppCloseDate = event.target.value; }
    handleStageChange(event) { this.oppStage = event.target.value; }

    get isFormValid() {
        return this.oppName && this.oppCloseDate && this.oppStage;
    }

    createOpportunity() {
        if (!this.isFormValid) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Missing fields',
                message: 'Please fill in name, close date, and stage.',
                variant: 'warning'
            }));
            return;
        }
        createOpportunityRecord({
            name: this.oppName,
            closeDate: this.oppCloseDate,
            stage: this.oppStage
        })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Opportunity created',
                    message: `${this.oppName} was created successfully.`,
                    variant: 'success'
                }));
                this.oppName = '';
                this.oppCloseDate = '';
                this.oppStage = '';
            })
            .catch((error) => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error creating Opportunity',
                    message: (error.body && error.body.message) || 'Unknown error',
                    variant: 'error'
                }));
            });
    }
}
