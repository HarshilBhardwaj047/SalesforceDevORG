import { LightningElement, track } from 'lwc';

export default class HelloWorld extends LightningElement {
    @track
    contacts = [
        {
            Id: 1,
            Name: 'Shashank Sharma',
            Title: 'VP of Engineering',
        },
        {
            Id: 2,
            Name: 'Michael Jones',
            Title: 'VP of Sales',
        },
        {
            Id: 3,
            Name: 'Jennifer Wu',
            Title: 'CEO',
        },
    ];
}