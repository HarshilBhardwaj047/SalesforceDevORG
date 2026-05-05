// opportunityList.js
// Lists Opportunities filtered by a keyword. Clicking a row navigates the
// user to the standard record page using the navigation service rather
// than the legacy pubsub pattern.
import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOpportunitiesByKeyword
    from '@salesforce/apex/OpportunityController.getOpportunitiesByKeyword';

const SEARCH_DEBOUNCE_MS = 300;

export default class OpportunityList extends NavigationMixin(LightningElement) {
    @track opportunities = [];
    @track error;
    @track keyword = '';
    debounceTimer;

    columns = [
        {
            label: 'Opportunity Name',
            fieldName: 'Name',
            type: 'button',
            typeAttributes: {
                label: { fieldName: 'Name' },
                variant: 'base',
                title: 'View Record',
                name: 'view_record'
            }
        },
        { label: 'Stage', fieldName: 'StageName' },
        { label: 'Close Date', fieldName: 'CloseDate', type: 'date' }
    ];

    connectedCallback() {
        this.refreshData();
    }

    refreshData() {
        getOpportunitiesByKeyword({ keyword: this.keyword })
            .then((result) => {
                this.opportunities = result;
                this.error = undefined;
            })
            .catch((error) => {
                this.error = error;
                this.opportunities = [];
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error loading opportunities',
                    message: (error && error.body && error.body.message) || 'Unknown error',
                    variant: 'error'
                }));
            });
    }

    handleSearch(event) {
        const value = event.target.value;
        // Debounce so we don't fire an Apex call on every keystroke
        clearTimeout(this.debounceTimer);
        this.debounceTimer = setTimeout(() => {
            this.keyword = value;
            this.refreshData();
        }, SEARCH_DEBOUNCE_MS);
    }

    handleRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        if (action === 'view_record') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.Id,
                    objectApiName: 'Opportunity',
                    actionName: 'view'
                }
            });
        }
    }
}
