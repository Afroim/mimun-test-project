import { LightningElement, api } from "lwc";
import CURRENT_USER_ID from "@salesforce/user/Id";
import LOCALE from "@salesforce/i18n/locale";
import canViewAllSalesSummaries from "@salesforce/customPermission/View_All_Sales_Summaries";
import getSalesSummary from "@salesforce/apex/MonthlySalesSummaryController.getSalesSummary";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import TITLE from "@salesforce/label/c.SalesSummary_Title";
import SALESPERSON from "@salesforce/label/c.SalesSummary_Salesperson";
import OWN_DATA_ONLY from "@salesforce/label/c.SalesSummary_OwnDataOnly";
import LOADING from "@salesforce/label/c.SalesSummary_Loading";
import MONTH from "@salesforce/label/c.SalesSummary_Month";
import YEAR from "@salesforce/label/c.SalesSummary_Year";
import TOTAL_SALES from "@salesforce/label/c.SalesSummary_TotalSales";
import TOTAL_12_MONTHS from "@salesforce/label/c.SalesSummary_Total12Months";
import NO_SALES_TITLE from "@salesforce/label/c.SalesSummary_NoSalesTitle";
import NO_SALES_MESSAGE from "@salesforce/label/c.SalesSummary_NoSalesMessage";
import LOOKUP_ERROR_TITLE from "@salesforce/label/c.SalesSummary_LookupErrorTitle";
import LOOKUP_ERROR_MESSAGE from "@salesforce/label/c.SalesSummary_LookupErrorMessage";
import LOAD_ERROR_TITLE from "@salesforce/label/c.SalesSummary_LoadErrorTitle";
import UNEXPECTED_ERROR from "@salesforce/label/c.SalesSummary_UnexpectedError";

export default class MonthlySalesSummary extends LightningElement {
  @api lowSalesThreshold = 1000;
  @api currencyCode = "ILS";

  labels = {
    title: TITLE,
    salesperson: SALESPERSON,
    ownDataOnly: OWN_DATA_ONLY,
    loading: LOADING,
    month: MONTH,
    year: YEAR,
    totalSales: TOTAL_SALES,
    total12Months: TOTAL_12_MONTHS,
    noSalesTitle: NO_SALES_TITLE,
    noSalesMessage: NO_SALES_MESSAGE,
    lookupErrorTitle: LOOKUP_ERROR_TITLE,
    lookupErrorMessage: LOOKUP_ERROR_MESSAGE,
    loadErrorTitle: LOAD_ERROR_TITLE,
    unexpectedError: UNEXPECTED_ERROR
  };

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
        label: this.labels.month,
        fieldName: "monthName",
        type: "text"
      },
      {
        label: this.labels.year,
        fieldName: "year",
        type: "text"
      },
      {
        label: this.labels.totalSales,
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
    this.selectedSalespersonId = event.detail.recordId || CURRENT_USER_ID;

    this.loadSalesSummary();
  }

  handleRecordPickerError(event) {
    const message =
      event.detail && event.detail.error && event.detail.error.message
        ? event.detail.error.message
        : this.labels.lookupErrorMessage;

    this.showToast(this.labels.lookupErrorTitle, message, "error");
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
          this.labels.noSalesTitle,
          this.labels.noSalesMessage,
          "info"
        );

        return;
      }

      const threshold = this.normalizedLowSalesThreshold;

      this.rows = (response.months || []).map((monthSummary) => {
        const year = Number(monthSummary.year);

        const monthNumber = Number(monthSummary.monthNumber);

        const amount = Number(monthSummary.amount || 0);

        const hasSales = monthSummary.hasSales === true;

        return {
          id: `${year}-${monthNumber}`,
          monthName: this.formatMonthName(year, monthNumber),
          year: String(year),
          amount,
          amountClass:
            hasSales && amount < threshold ? "slds-text-color_error" : ""
        };
      });

      this.totalAmount = Number(response.totalAmount || 0);

      this.hasSalesData = true;
    } catch (error) {
      if (currentRequest !== this.requestSequence) {
        return;
      }

      this.showToast(
        this.labels.loadErrorTitle,
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

    return this.labels.unexpectedError;
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
