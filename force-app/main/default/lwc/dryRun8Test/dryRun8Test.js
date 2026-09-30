import { LightningElement } from 'lwc';
import getContacts from '@salesforce/apex/DryRun8TestClass.getContacts';

const API_ENDPOINT = 'https://api.mycompany-internal.com/v1/contacts';

export default class DryRun8Test extends LightningElement {
    contacts;

    connectedCallback() {
        getContacts().then(data => {
            this.contacts = data;
        });
    }

    highlightRow() {
        const row = document.querySelector('.highlight');
        if (row) {
            row.classList.add('active');
        }
    }
}
