import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTodayCheck from '@salesforce/apex/healthCheckManualInputController.getTodayCheck';
import saveManualLogs from '@salesforce/apex/healthCheckManualInputController.saveManualLogs';
import sendEmail from '@salesforce/apex/healthCheckManualInputController.sendEmail';
import runAutomatedChecks from '@salesforce/apex/healthCheckManualInputController.runAutomatedChecks';
const STATUS_OPTIONS = [
    { label: 'Green',   value: 'Green'   },
    { label: 'Amber',   value: 'Amber'   },
    { label: 'Red',     value: 'Red'     },
    { label: 'N/A',     value: 'N/A'     },
    { label: 'Pending', value: 'Pending' }
];

const STATUS_BADGE_MAP = {
    Green:   'slds-badge slds-badge_success',
    Amber:   'slds-badge badge-amber',
    Red:     'slds-badge badge-red',
    'N/A':   'slds-badge',
    Pending: 'slds-badge badge-pending'
};

const STATUS_ROW_MAP = {
    Green:   'row-green',
    Amber:   'row-amber',
    Red:     'row-red',
    'N/A':   '',
    Pending: 'row-pending'
};

export default class HealthCheckManualInput extends LightningElement {

    @track isLoading = true;
    @track toastMessage = '';
    @track toastClass   = '';

    // ── Data ─────────────────────────────────────────────────────────────────
    @track master        = {};
    @track automatedLogs = [];
    @track manualLogs    = [];

    // Track unsaved manual changes: map of Id → mutated Health_Check_Log__c
    @track dirtyMap = {};

    // ─────────────────────────────────────────────────────────────────────────

    connectedCallback() {
        this.loadData();
    }

    // ── Data loading ──────────────────────────────────────────────────────────

    loadData() {
        this.isLoading = true;
        getTodayCheck()
            .then(result => {
                this.master   = result.master;
                this.automatedLogs = this.enrichAutomated(result.automatedLogs || []);
                console.log('Saharsh' + JSON.stringify(this.automatedLogs));
                this.manualLogs    = this.enrichManual(result.manualLogs    || []);
                this.dirtyMap      = {};
                this.isLoading     = false;
            })
            .catch(err => {
                this.isLoading = false;
                this.showError('Failed to load health check data: ' + this.errorMsg(err));
            });
    }

    // ── Computed properties ───────────────────────────────────────────────────

    get checkDateLabel() {
        return this.master?.KPMG_Check_Date__c || new Date().toLocaleDateString();
    }

    get emailSent() {
        return this.master?.KPMG_Email_Sent__c === true;
    }

    get overallStatusLabel() {
        const all = [...this.automatedLogs, ...this.manualLogs];
        if (all.some(l => l.KPMG_Status__c === 'Red'))   return 'Red — Action Required';
        if (all.some(l => l.KPMG_Status__c === 'Amber')) return 'Amber — Attention Needed';
        return 'Green — All Clear';
    }

    get overallIcon() {
        const lbl = this.overallStatusLabel;
        if (lbl.includes('Red'))   return 'utility:error';
        if (lbl.includes('Amber')) return 'utility:warning';
        return 'utility:success';
    }

    get overallBannerClass() {
        const lbl = this.overallStatusLabel;
        if (lbl.includes('Red'))   return 'overall-banner banner-red';
        if (lbl.includes('Amber')) return 'overall-banner banner-amber';
        return 'overall-banner banner-green';
    }

    get automatedCount() { return this.automatedLogs.length; }
    get manualCount()    { return this.manualLogs.length;    }

    get hasPending() {
        return this.manualLogs.some(l => l.KPMG_Status__c === 'Pending');
    }

    get pendingBadgeLabel() {
        const cnt = this.manualLogs.filter(l => l.KPMG_Status__c === 'Pending').length;
        return cnt + ' pending manual section' + (cnt === 1 ? '' : 's');
    }

    get isSendDisabled() {
        return this.isLoading;
    }

    get statusOptions() { return STATUS_OPTIONS; }

    // Group manual logs by Section for display
    get manualSectionGroups() {
        const map = {};
        const order = [];
        for (const log of this.manualLogs) {
            const sec = log.KPMG_Section__c;
            if (!map[sec]) { map[sec] = []; order.push(sec); }
            map[sec].push(log);
        }
        return order.map(sec => ({ sectionName: sec, items: map[sec] }));
    }

    // ── Event handlers ────────────────────────────────────────────────────────

    handleManualFieldChange(event) {
        const id    = event.target.dataset.id;
        const field = event.target.dataset.field;
        const value = event.target.value;
        this.updateDirtyLog(id, field, value);
    }

    handleManualCheckboxChange(event) {
        const id    = event.target.dataset.id;
        const field = event.target.dataset.field;
        const value = event.target.checked;
        this.updateDirtyLog(id, field, value);
    }

    handleSave() {
        const dirty = Object.values(this.dirtyMap);
        if (dirty.length === 0) {
            this.showInfo('No changes to save.');
            return;
        }
        this.isLoading = true;
        saveManualLogs({ logs: dirty })
            .then(() => {
                this.showSuccess('Manual entries saved.');
                this.loadData();
            })
            .catch(err => {
                this.isLoading = false;
                this.showError('Save failed: ' + this.errorMsg(err));
            });
    }

    handleSendEmail() {
        if (!confirm('Send the Sales Cloud Daily Health Check email now?\n\n'
            + 'This will include all automated and manual sections. '
            + 'Pending sections will appear as "Awaiting Input" in the email.')) {
            return;
        }
        this.isLoading = true;
        const dirty = Object.values(this.dirtyMap);
        sendEmail({ dailyCheckId: this.master.Id, pendingLogs: dirty })
            .then(() => {
                this.showSuccess('Health Check email sent successfully! ✉️');
                this.loadData();
            })
            .catch(err => {
                this.isLoading = false;
                this.showError('Email send failed: ' + this.errorMsg(err));
            });
    }

    handleRefreshAutomated() {
        if (!confirm('Re-run all automated health checks now?')) return;
        this.isLoading = true;
        runAutomatedChecks({ dailyCheckId: this.master.Id })
            .then(() => {
                this.showInfo('Automated checks queued. Refresh in ~30 seconds to see results.');
                this.isLoading = false;
            })
            .catch(err => {
                this.isLoading = false;
                this.showError('Failed to queue checks: ' + this.errorMsg(err));
            });
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    updateDirtyLog(id, field, value) {
        if (!this.dirtyMap[id]) {
            // Find the original in manualLogs
            const orig = this.manualLogs.find(l => l.Id === id);
            this.dirtyMap[id] = orig ? { ...orig } : { Id: id };
        }
        this.dirtyMap[id][field] = value;

        // Also update the UI-tracked manualLogs array
        this.manualLogs = this.manualLogs.map(l => {
            if (l.Id === id) {
                const updated = { ...l, [field]: value };
                updated.badgeClass = STATUS_BADGE_MAP[updated.KPMG_Status__c] || 'slds-badge';
                return updated;
            }
            return l;
        });
    }

    enrichAutomated(logs) {
        return logs.map(l => ({
            ...l,
            badgeClass:        STATUS_BADGE_MAP[l.KPMG_Status__c] || 'slds-badge',
            rowClass:          STATUS_ROW_MAP[l.KPMG_Status__c]   || '',
            totalFormatted:    l.KPMG_Total__c     != null ? l.KPMG_Total__c.toLocaleString()     : '—',
            usedFormatted:     l.KPMG_Used__c      != null ? l.KPMG_Used__c.toLocaleString()      : '—',
            remainingFormatted:l.KPMG_Remaining__c != null ? l.KPMG_Remaining__c.toLocaleString() : '—'
        }));
    }

    enrichManual(logs) {
        return logs.map(l => ({
            ...l,
            badgeClass: STATUS_BADGE_MAP[l.KPMG_Status__c] || 'slds-badge',
            rowClass:   STATUS_ROW_MAP[l.KPMG_Status__c]   || ''
        }));
    }

    showSuccess(msg) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: msg, variant: 'success' }));
    }

    showError(msg) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error', mode: 'sticky' }));
    }

    showInfo(msg) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Info', message: msg, variant: 'info' }));
    }

    errorMsg(err) {
        return (err?.body?.message) || (err?.message) || JSON.stringify(err);
    }
}