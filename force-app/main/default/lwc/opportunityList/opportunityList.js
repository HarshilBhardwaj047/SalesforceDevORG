import { LightningElement, wire, track } from 'lwc';
import searchOpportunities from '@salesforce/apex/OpportunityController.searchOpportunities';
import { publish, MessageContext } from 'lightning/messageService';
import OPP_SELECTED_MESSAGE from '@salesforce/messageChannel/OpportunitySelected__c';

export default class OpportunityList extends LightningElement {
    @track searchKeyword = '';
    @track opportunities = [];
    @wire(MessageContext) messageContext;

    @wire(searchOpportunities, { keyword: '$searchKeyword' })
    wiredOpportunities({ error, data }) {
        if (data) {
            this.opportunities = data;
        } else if (error) {
            // handle error
        }
    }

    handleSearch(event) {
        this.searchKeyword = event.target.value;
    }

    handleClick(event) {
        const oppId = event.target.dataset.id;
        const payload = { recordId: oppId };
        publish(this.messageContext, OPP_SELECTED_MESSAGE, payload);
    }
}
