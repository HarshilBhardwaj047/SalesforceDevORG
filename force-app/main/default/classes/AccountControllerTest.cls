@isTest
private class AccountControllerTest {
    @TestSetup
    static void setup() {
        insert new List<Account>{
            new Account(Name = 'Acme Tech', Industry = 'Technology'),
            new Account(Name = 'Acme Retail', Industry = 'Retail'),
            new Account(Name = 'Acme Retail Two', Industry = 'Retail')
        };
    }

    @isTest
    static void getAccountsByIndustry_returnsMatchingAccounts() {
        Test.startTest();
        List<Account> results = AccountController.getAccountsByIndustry('Retail');
        Test.stopTest();
        System.assertEquals(2, results.size(), 'Should return only Retail accounts');
    }

    @isTest
    static void getAccountsByIndustry_returnsEmptyListForBlankIndustry() {
        Test.startTest();
        List<Account> results = AccountController.getAccountsByIndustry('');
        Test.stopTest();
        System.assert(results.isEmpty(), 'Blank industry should return no accounts');
    }

    @isTest
    static void getAccountsByIndustry_returnsEmptyListWhenNoMatch() {
        Test.startTest();
        List<Account> results = AccountController.getAccountsByIndustry('Nonexistent Industry');
        Test.stopTest();
        System.assert(results.isEmpty(), 'Unmatched industry should return no accounts');
    }
}
