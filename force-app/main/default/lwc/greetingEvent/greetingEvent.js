import { LightningElement } from 'lwc';

export default class GreetingEvent extends LightningElement {
    greeting = 'World';
  changeHandler(event) {
    this.greeting = event.target.value;
  }
}