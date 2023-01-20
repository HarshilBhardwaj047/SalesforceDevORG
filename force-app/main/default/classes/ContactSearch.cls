public class ContactSearch {
    public static List<Contact> searchForContacts(String lname, String mcode) {
        try {
            List <Contact> cont = [SELECT Id, Name
                                   FROM Contact 
                                   WHERE LastName =:lname AND MailingPostalCode=: mcode]; 
                                   return cont;
            
        } catch (DMLException e) {
            System.debug('empty string');
            return null;
        }
    }
}