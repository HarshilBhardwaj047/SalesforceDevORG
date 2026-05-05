public with sharing class TestPageController {
    public List<Account> accountList {
        get {
            return [
                SELECT Id, Name
                FROM Account
                WITH USER_MODE
                ORDER BY Name
                LIMIT 200
            ];
        }
    }
}
