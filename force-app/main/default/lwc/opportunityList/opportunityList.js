// opportunityList.js
import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { fireEvent } from 'c/pubsub';
import getOpportunitiesByKeyword from '@salesforce/apex/OpportunityController.getOpportunitiesByKeyword';

export default class OpportunityList extends LightningElement {
    @track opportunities = [];
    @track error;

    columns = [
        {
            label: 'Opportunity name',
            fieldName: 'Name',
            type: 'button',
            typeAttributes: {
                label: { fieldName: 'Name' },
                variant: 'base',
                title: 'View Record',
                name: 'view_record',
            },
        },
        { label: 'Stage', fieldName: 'StageName' },
        { label: 'Close Date', fieldName: 'CloseDate', type: 'date' },
    ];

    @wire(CurrentPageReference) pageRef;

    connectedCallback() {
        this.refreshData();
    }

    refreshData() {
        getOpportunitiesByKeyword()
            .then(result => {
                this.opportunities = result;
                this.error = undefined;
            })
            .catch(error => {
                this.error = error;
                this.opportunities = undefined;
            });
    }

    handleRowAction(event) {
        const row = event.detail.row;
        fireEvent(this.pageRef, 'opportunitySelected', row.Id);
    }
}