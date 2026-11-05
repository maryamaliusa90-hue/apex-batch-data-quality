/**
 * Nightly batch that normalizes Contact email/phone and flags records with
 * data quality issues. Uses partial-success DML so one bad record never
 * fails a whole chunk, and reports totals when the job finishes.
 */
public with sharing class ContactDataQualityBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {
    @TestVisible
    private Integer scanned = 0;
    @TestVisible
    private Integer updated = 0;
    @TestVisible
    private Integer flagged = 0;
    @TestVisible
    private List<String> errors = new List<String>();

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator(
            [SELECT Id, Email, Phone, Data_Quality_Status__c FROM Contact WITH USER_MODE ORDER BY Id]
        );
    }

    public void execute(Database.BatchableContext ctx, List<Contact> scope) {
        List<Contact> toUpdate = new List<Contact>();
        for (Contact c : scope) {
            scanned++;
            Boolean changed = ContactDataQualityRules.normalize(c);
            String issues = ContactDataQualityRules.findIssues(c);
            if (issues != null) {
                flagged++;
            }
            if (issues != c.Data_Quality_Status__c) {
                c.Data_Quality_Status__c = issues;
                changed = true;
            }
            if (changed) {
                toUpdate.add(c);
            }
        }

        List<Database.SaveResult> results = Database.update(toUpdate, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                updated++;
            } else if (errors.size() < 100) {
                errors.add(toUpdate[i].Id + ': ' + results[i].getErrors()[0].getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug(
            LoggingLevel.INFO,
            'ContactDataQualityBatch finished. scanned=' +
                scanned +
                ' updated=' +
                updated +
                ' flagged=' +
                flagged +
                ' errors=' +
                errors.size()
        );
    }

    /** Schedulable entry point, e.g. System.schedule('Contact DQ nightly', '0 0 2 * * ?', new ContactDataQualityBatch()); */
    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new ContactDataQualityBatch(), 200);
    }
}
