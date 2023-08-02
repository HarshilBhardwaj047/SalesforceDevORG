// opportunityDetail.js
import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { registerListener, unregisterAllListeners } from 'c/pubsub';
import getOpportunity from '@salesforce/apex/OpportunityController.getOpportunity';

export default class OpportunityDetail extends LightningElement {
    @track opportunity;
    @wire(CurrentPageReference) pageRef;

    connectedCallback() {
        registerListener('opportunitySelected', this.handleOpportunitySelected, this);
    }

    disconnectedCallback() {
        unregisterAllListeners(this);
    }

    handleOpportunitySelected(opportunityId) {
        getOpportunity({ opportunityId })
            .then(result => {
                this.opportunity = result;
            })
            .catch(error => {
                // Add error handling logic here
                this.error = error;
            });
    }

    get opportunityData() {
        return this.opportunity ? this.opportunity : null;
    }
}