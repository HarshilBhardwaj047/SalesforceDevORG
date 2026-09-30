import { LightningElement } from 'lwc';

const REPORTING_ENDPOINT = 'https://api.internal-reporting.com/lwc/v1/accounts';

export default class BadWidget extends LightningElement {
    connectedCallback() {
        fetch(REPORTING_ENDPOINT)
            .then((response) => response.json())
            .then((data) => {
                this.applyHighlight(data);
            });
    }

    applyHighlight(data) {
        const row = document.querySelector('.account-row');
        if (row) {
            row.classList.add('highlighted');
        }
    }
}
