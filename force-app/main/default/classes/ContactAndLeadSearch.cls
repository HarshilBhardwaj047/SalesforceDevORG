public class ContactAndLeadSearch {
    public static List<List<sObject>> searchContactsAndLeads(String inpt) {
        try{
       List<List<SObject>> SoslList = [FIND 'Smith' IN NAME FIELDS RETURNING Contact(LastName), Lead(LastName) ];
       return SoslList;
        } catch(Exception e){
            System.debug('Input Empty');
            return null;
        }
    }
}