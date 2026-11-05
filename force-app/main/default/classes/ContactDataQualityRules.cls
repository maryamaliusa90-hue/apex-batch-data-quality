/**
 * Pure, side-effect-free data quality rules for Contacts.
 * Kept separate from the batch so every rule is unit-testable without DML.
 */
public with sharing class ContactDataQualityRules {
    // Throwaway domains that should never be used for customer contact.
    @TestVisible
    private static final Set<String> BLOCKED_EMAIL_DOMAINS = new Set<String>{
        'mailinator.com',
        'guerrillamail.com',
        'yopmail.com',
        '10minutemail.com'
    };

    /** Normalizes fields in place. Returns true if anything changed. */
    public static Boolean normalize(Contact c) {
        Boolean changed = false;
        if (c.Email != null) {
            String email = c.Email.trim().toLowerCase();
            if (email != c.Email) {
                c.Email = email;
                changed = true;
            }
        }
        if (c.Phone != null) {
            String phone = normalizeUsPhone(c.Phone);
            if (phone != null && phone != c.Phone) {
                c.Phone = phone;
                changed = true;
            }
        }
        return changed;
    }

    /** Returns a semicolon-separated list of issues, or null when the record is clean. */
    public static String findIssues(Contact c) {
        List<String> issues = new List<String>();
        if (String.isBlank(c.Email) && String.isBlank(c.Phone)) {
            issues.add('No email or phone');
        }
        if (String.isNotBlank(c.Email) && BLOCKED_EMAIL_DOMAINS.contains(c.Email.substringAfter('@').toLowerCase())) {
            issues.add('Disposable email domain');
        }
        if (String.isNotBlank(c.Phone) && normalizeUsPhone(c.Phone) == null) {
            issues.add('Unrecognized phone format');
        }
        return issues.isEmpty() ? null : String.join(issues, '; ');
    }

    /** Formats a 10-digit (or 1 + 10-digit) U.S. number as (XXX) XXX-XXXX; returns null otherwise. */
    @TestVisible
    private static String normalizeUsPhone(String raw) {
        String digits = raw.replaceAll('[^0-9]', '');
        if (digits.length() == 11 && digits.startsWith('1')) {
            digits = digits.substring(1);
        }
        if (digits.length() != 10) {
            return null;
        }
        return '(' + digits.substring(0, 3) + ') ' + digits.substring(3, 6) + '-' + digits.substring(6);
    }
}
