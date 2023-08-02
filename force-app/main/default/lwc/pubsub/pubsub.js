let events = {};

/**
 * Confirm the event exists, and then add the callback
 * @param {string} eventName - Name of the event.
 * @param {function} callback - Function that should be executed.
 * @param {object} thisArg - The context that function will be executed in.
 */
const registerListener = (eventName, callback, thisArg) => {
    // Checking if the event is already registered. 
    if (events[eventName]) {
        events[eventName].push({ callback: callback, thisArg: thisArg });
    } else {
        // New event, create a new array for the event name.
        events[eventName] = [{ callback: callback, thisArg: thisArg }];
    }
};

/**
 * If the event exists, clear the listeners array
 * @param {string} eventName - Name of the event.
 */
const unregisterAllListeners = (eventName) => {
    if (events[eventName]) {
        events[eventName] = [];
    }
};

/**
 * Fire an event to all registered listeners.
 * @param {string} eventName - Name of the event.
 * @param {*} payload - The payload that will be sent to all listeners.
 */
const fireEvent = (eventName, payload) => {
    if (events[eventName]) {
        events[eventName].forEach(listener => {
            try {
                listener.callback.call(listener.thisArg, payload);
            } catch (error) {
                // Developer can add error handling here if needed.
            }
        });
    }
};

export { registerListener, unregisterAllListeners, fireEvent };