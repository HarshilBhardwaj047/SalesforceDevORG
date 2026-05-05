// opportunityDetail.js
// Place this on an Opportunity record page — it gets recordId from the
// page context. Uses @wire for reactivity (no manual refresh needed) and
// surfaces errors via toast.
import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOpportunity from '@salesforce/apex/OpportunityController.getOpportunity';

export default class OpportunityDetail extends LightningElement {
    @api recordId;
    opportunity;
    error;

    @wire(getOpportunity, { opportunityId: '$recordId' })
    wiredOpportunity({ data, error }) {
        if (data) {
            this.opportunity = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.opportunity = undefined;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error loading Opportunity',
                message: (error.body && error.body.message) || 'Unknown error',
                variant: 'error'
            }));
        }
    }

    get hasOpportunity() {
        return this.opportunity != null;
    }
}
