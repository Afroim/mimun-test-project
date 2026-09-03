import { LightningElement, api } from "lwc";
import CURRENT_USER_ID from "@salesforce/user/Id";
import LOCALE from "@salesforce/i18n/locale";
import canViewAllSalesSummaries from "@salesforce/customPermission/View_All_Sales_Summaries";
import getSalesSummary from "@salesforce/apex/MonthlySalesSummaryController.getSalesSummary";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

export default class MonthlySalesSummary extends LightningElement {
  @api lowSalesThreshold = 1000;
  @api currencyCode = "ILS";

  selectedSalespersonId = CURRENT_USER_ID;
  rows = [];
  totalAmount = 0;
  hasSalesData = false;
  isLoading = false;

  requestSequence = 0;

  activeUserFilter = {
    criteria: [
      {
        fieldPath: "IsActive",
        operator: "eq",
        value: true
      }
    ]
  };

  monthFormatter = new Intl.DateTimeFormat(LOCALE, {
    month: "long",
    timeZone: "UTC"
  });

  connectedCallback() {
    this.loadSalesSummary();
  }

  get canSelectSalesperson() {
    return canViewAllSalesSummaries === true;
  }

  get isSalespersonSelectionDisabled() {
    return !this.canSelectSalesperson;
  }

  get normalizedLowSalesThreshold() {
    const threshold = Number(this.lowSalesThreshold);

    return Number.isFinite(threshold) ? threshold : 1000;
  }

  get effectiveCurrencyCode() {
    const configuredCurrencyCode =
      typeof this.currencyCode === "string"
        ? this.currencyCode.trim().toUpperCase()
        : "";

    return configuredCurrencyCode || "ILS";
  }

  get columns() {
    return [
      {
        label: "Month",
        fieldName: "monthName",
        type: "text"
      },
      {
        label: "Year",
        fieldName: "year",
        type: "text"
      },
      {
        label: "Total Sales",
        fieldName: "amount",
        type: "currency",
        typeAttributes: {
          currencyCode: this.effectiveCurrencyCode,
          currencyDisplayAs: "symbol",
          minimumFractionDigits: 2,
          maximumFractionDigits: 2
        },
        cellAttributes: {
          alignment: "right",
          class: {
            fieldName: "amountClass"
          }
        }
      }
    ];
  }

  handleSalespersonChange(event) {
    const selectedRecordId = event.detail.recordId;

    this.selectedSalespersonId = selectedRecordId || CURRENT_USER_ID;

    this.loadSalesSummary();
  }

  handleRecordPickerError(event) {
    const pickerError =
      event.detail && event.detail.error && event.detail.error.message
        ? event.detail.error.message
        : "Unable to load active salespeople.";

    this.showToast("Salesperson lookup error", pickerError, "error");
  }

  async loadSalesSummary() {
    const currentRequest = ++this.requestSequence;

    this.isLoading = true;
    this.hasSalesData = false;
    this.rows = [];
    this.totalAmount = 0;

    try {
      const response = await getSalesSummary({
        salespersonId: this.selectedSalespersonId
      });

      if (currentRequest !== this.requestSequence) {
        return;
      }

      if (!response || response.hasSales !== true) {
        this.showToast(
          "No sales found",
          "No sales were found for the selected salesperson during the last 12 months.",
          "info"
        );

        return;
      }

      const threshold = this.normalizedLowSalesThreshold;

      const currencyCode = this.effectiveCurrencyCode;

      this.rows = (response.months || []).map((monthSummary) => {
        const year = Number(monthSummary.year);

        const monthNumber = Number(monthSummary.monthNumber);

        const amount = Number(monthSummary.amount || 0);

        const hasSales = monthSummary.hasSales === true;

        const isBelowThreshold = hasSales && amount < threshold;

        return {
          id: `${year}-${monthNumber}`,
          monthName: this.formatMonthName(year, monthNumber),
          year: String(year),
          amount,
          currencyCode,
          amountClass: isBelowThreshold ? "slds-text-color_error" : ""
        };
      });

      this.totalAmount = Number(response.totalAmount || 0);

      this.hasSalesData = true;
    } catch (error) {
      if (currentRequest !== this.requestSequence) {
        return;
      }

      this.showToast(
        "Unable to load sales summary",
        this.getErrorMessage(error),
        "error"
      );
    } finally {
      if (currentRequest === this.requestSequence) {
        this.isLoading = false;
      }
    }
  }

  formatMonthName(year, monthNumber) {
    const monthDate = new Date(Date.UTC(year, monthNumber - 1, 1));

    return this.monthFormatter.format(monthDate);
  }

  getErrorMessage(error) {
    if (error && Array.isArray(error.body)) {
      return error.body
        .map((item) => item.message)
        .filter((message) => Boolean(message))
        .join(", ");
    }

    if (error && error.body && typeof error.body.message === "string") {
      return error.body.message;
    }

    if (error && typeof error.message === "string") {
      return error.message;
    }

    return "An unexpected error occurred while loading the sales summary.";
  }

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant
      })
    );
  }
}
