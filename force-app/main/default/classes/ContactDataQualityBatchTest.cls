@IsTest
private class ContactDataQualityBatchTest {
    @TestSetup
    static void setup() {
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 150; i++) {
            contacts.add(
                new Contact(
                    LastName = 'Clean' + i,
                    Email = 'USER' + i + '@Example.COM',
                    Phone = '1-312-555-01' + String.valueOf(10 + Math.mod(i, 90))
                )
            );
        }
        contacts.add(new Contact(LastName = 'NoContactInfo'));
        contacts.add(new Contact(LastName = 'BadEmail', Email = 'someone@mailinator.com', Phone = '3125550100'));
        contacts.add(new Contact(LastName = 'BadPhone', Email = 'ok@example.com', Phone = '12345'));
        insert contacts;
    }

    @IsTest
    static void batchNormalizesAndFlags() {
        ContactDataQualityBatch job = new ContactDataQualityBatch();

        Test.startTest();
        Database.executeBatch(job, 200);
        Test.stopTest();

        Contact clean = [SELECT Email, Phone, Data_Quality_Status__c FROM Contact WHERE LastName = 'Clean0'];
        Assert.areEqual('user0@example.com', clean.Email);
        Assert.areEqual('(312) 555-0110', clean.Phone);
        Assert.isNull(clean.Data_Quality_Status__c);

        Assert.areEqual(
            'No email or phone',
            [SELECT Data_Quality_Status__c FROM Contact WHERE LastName = 'NoContactInfo'].Data_Quality_Status__c
        );
        Assert.areEqual(
            'Disposable email domain',
            [SELECT Data_Quality_Status__c FROM Contact WHERE LastName = 'BadEmail'].Data_Quality_Status__c
        );
        Assert.areEqual(
            'Unrecognized phone format',
            [SELECT Data_Quality_Status__c FROM Contact WHERE LastName = 'BadPhone'].Data_Quality_Status__c
        );
        Assert.areEqual(3, [SELECT COUNT() FROM Contact WHERE Data_Quality_Status__c != NULL]);
    }

    @IsTest
    static void rerunClearsResolvedIssues() {
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'BadEmail'];
        c.Data_Quality_Status__c = 'Disposable email domain';
        c.Email = 'fixed@example.com';
        update c;

        Test.startTest();
        Database.executeBatch(new ContactDataQualityBatch(), 200);
        Test.stopTest();

        Assert.isNull([SELECT Data_Quality_Status__c FROM Contact WHERE Id = :c.Id].Data_Quality_Status__c);
    }

    @IsTest
    static void schedulerEnqueuesBatch() {
        Test.startTest();
        String jobId = System.schedule('DQ test', '0 0 2 * * ?', new ContactDataQualityBatch());
        Test.stopTest();
        Assert.isNotNull(jobId);
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE JobType = 'BatchApex' AND ApexClass.Name = 'ContactDataQualityBatch'
            ]
        );
    }

    @IsTest
    static void phoneRules() {
        Assert.areEqual('(312) 555-0100', ContactDataQualityRules.normalizeUsPhone('+1 (312) 555-0100'));
        Assert.areEqual('(312) 555-0100', ContactDataQualityRules.normalizeUsPhone('312.555.0100'));
        Assert.isNull(ContactDataQualityRules.normalizeUsPhone('555-0100'));
    }
}
