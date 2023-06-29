import { LightningElement, wire, api, track } from 'lwc';
import { subscribe, MessageContext } from 'lightning/messageService';
import OPP_SELECTED_MESSAGE from '@salesforce/messageChannel/OpportunitySelected__c';
import getOpportunity from '@salesforce/apex/OpportunityController.getOpportunity';

export default class OpportunityDetails extends LightningElement {
    subscription = null;
    @track opportunity;
    @wire(MessageContext) messageContext;

    connectedCallback() {
        this.subscribeToMessageChannel();
    }

    subscribeToMessageChannel() {
        if (!this.subscription) {
            this.subscription = subscribe(
                this.messageContext,
                OPP_SELECTED_MESSAGE,
                (message) => this.handleMessage(message)
            );
        }
    }

    handleMessage(message) {
        this.getOpportunityDetails(message.recordId);
    }

    @wire(getOpportunity, { recordId: '$recordId' })
    wiredOpportunity({ error, data }) {
        if (data) {
            this.opportunity = data;
        } else if (error) {
            // handle error
        }
    }
}
