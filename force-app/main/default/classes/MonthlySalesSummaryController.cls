/**
 * Provides aggregated monthly sales data for the Sales Summary LWC.
 *
 * Security model:
 * - A regular user can request only their own sales.
 * - A user with View_All_Sales_Summaries Custom Permission can request
 *   sales for any active Salesforce user.
 * - Record sharing is intentionally bypassed because Sale__c ownership
 *   doesn't necessarily match the current owner of the related Account.
 * - Access is restricted explicitly by Account__r.OwnerId.
 */
public without sharing class MonthlySalesSummaryController {
  private static final Integer NUMBER_OF_MONTHS = 12;
  private static final String VIEW_ALL_PERMISSION = 'View_All_Sales_Summaries';

  /**
   * Returns the sales summary for the requested salesperson.
   *
   * @param salespersonId selected User Id; null means current user.
   */
  @AuraEnabled(cacheable=true)
  public static SalesSummaryResponse getSalesSummary(Id salespersonId) {
    validateReadAccess();

    Id effectiveSalespersonId = resolveSalespersonId(salespersonId);

    validateActiveSalesperson(effectiveSalespersonId);

    Date currentMonth = Date.today().toStartOfMonth();
    Date startDate = currentMonth.addMonths(-(NUMBER_OF_MONTHS - 1));
    Date endDateExclusive = currentMonth.addMonths(1);

    List<AggregateResult> aggregateResults = [
      SELECT
        CALENDAR_YEAR(Sale_Date__c) saleYear,
        CALENDAR_MONTH(Sale_Date__c) saleMonth,
        SUM(Amount__c) totalAmount,
        COUNT(Id) saleCount
      FROM Sale__c
      WHERE
        Account__r.OwnerId = :effectiveSalespersonId
        AND Sale_Date__c >= :startDate
        AND Sale_Date__c < :endDateExclusive
      GROUP BY CALENDAR_YEAR(Sale_Date__c), CALENDAR_MONTH(Sale_Date__c)
      ORDER BY CALENDAR_YEAR(Sale_Date__c), CALENDAR_MONTH(Sale_Date__c)
    ];

    Map<String, AggregateMonthData> aggregateDataByMonth = buildAggregateDataMap(
      aggregateResults
    );

    SalesSummaryResponse response = new SalesSummaryResponse();
    response.salespersonId = effectiveSalespersonId;
    response.startDate = startDate;
    response.endDate = currentMonth.addMonths(1).addDays(-1);
    response.months = new List<MonthSummary>();
    response.totalAmount = 0;
    response.totalSaleCount = 0;

    for (
      Integer monthOffset = 0; monthOffset < NUMBER_OF_MONTHS; monthOffset++
    ) {
      Date monthDate = startDate.addMonths(monthOffset);
      String monthKey = createMonthKey(monthDate.year(), monthDate.month());

      AggregateMonthData aggregateData = aggregateDataByMonth.get(monthKey);

      Decimal monthAmount = aggregateData == null
        ? 0
        : aggregateData.totalAmount;

      Integer monthSaleCount = aggregateData == null
        ? 0
        : aggregateData.saleCount;

      MonthSummary monthSummary = new MonthSummary();
      monthSummary.year = monthDate.year();
      monthSummary.monthNumber = monthDate.month();
      monthSummary.amount = monthAmount;
      monthSummary.saleCount = monthSaleCount;
      monthSummary.hasSales = monthSaleCount > 0;

      response.months.add(monthSummary);
      response.totalAmount += monthAmount;
      response.totalSaleCount += monthSaleCount;
    }

    response.hasSales = response.totalSaleCount > 0;

    return response;
  }

  /**
   * Resolves the salesperson according to the current user's permissions.
   */
  private static Id resolveSalespersonId(Id requestedSalespersonId) {
    Id currentUserId = UserInfo.getUserId();

    if (
      requestedSalespersonId == null ||
      requestedSalespersonId == currentUserId
    ) {
      return currentUserId;
    }

    Boolean canViewAllSalesSummaries = FeatureManagement.checkPermission(
      VIEW_ALL_PERMISSION
    );

    if (!canViewAllSalesSummaries) {
      throw new AuraHandledException(
        'You are not authorized to view another salesperson.'
      );
    }

    return requestedSalespersonId;
  }

  /**
   * Prevents requests for inactive users or non-User record IDs.
   */
  private static void validateActiveSalesperson(Id salespersonId) {
    if (
      salespersonId == null ||
      salespersonId.getSObjectType() != User.SObjectType
    ) {
      throw new AuraHandledException('The selected salesperson is invalid.');
    }

    List<User> activeUsers = [
      SELECT Id
      FROM User
      WHERE Id = :salespersonId AND IsActive = TRUE
      LIMIT 1
    ];

    if (activeUsers.isEmpty()) {
      throw new AuraHandledException('The selected salesperson is not active.');
    }
  }

  /**
   * Checks object and field-level read permissions.
   *
   * Aggregate SOQL runs in system mode because record access is implemented
   * explicitly by the current Account owner business rule.
   */
  private static void validateReadAccess() {
    Boolean hasAccess =
      Sale__c.SObjectType.getDescribe().isAccessible() &&
      Sale__c.Account__c.getDescribe().isAccessible() &&
      Sale__c.Amount__c.getDescribe().isAccessible() &&
      Sale__c.Sale_Date__c.getDescribe().isAccessible() &&
      Account.SObjectType.getDescribe().isAccessible() &&
      Account.OwnerId.getDescribe().isAccessible();

    if (!hasAccess) {
      throw new AuraHandledException(
        'You do not have permission to access sales data.'
      );
    }
  }

  /**
   * Converts AggregateResult rows into a map for efficient lookup.
   */
  private static Map<String, AggregateMonthData> buildAggregateDataMap(
    List<AggregateResult> aggregateResults
  ) {
    Map<String, AggregateMonthData> result = new Map<String, AggregateMonthData>();

    for (AggregateResult aggregateRow : aggregateResults) {
      Integer saleYear = (Integer) aggregateRow.get('saleYear');

      Integer saleMonth = (Integer) aggregateRow.get('saleMonth');

      Decimal totalAmount = (Decimal) aggregateRow.get('totalAmount');

      Integer saleCount = (Integer) aggregateRow.get('saleCount');

      AggregateMonthData monthData = new AggregateMonthData();

      monthData.totalAmount = totalAmount == null ? 0 : totalAmount;

      monthData.saleCount = saleCount == null ? 0 : saleCount;

      result.put(createMonthKey(saleYear, saleMonth), monthData);
    }

    return result;
  }

  private static String createMonthKey(Integer year, Integer month) {
    return String.valueOf(year) + '-' + String.valueOf(month);
  }

  /**
   * Internal representation of an aggregated SOQL row.
   */
  private class AggregateMonthData {
    private Decimal totalAmount;
    private Integer saleCount;
  }

  /**
   * Complete response returned to the LWC.
   */
  public class SalesSummaryResponse {
    @AuraEnabled
    public Id salespersonId { get; set; }

    @AuraEnabled
    public Date startDate { get; set; }

    @AuraEnabled
    public Date endDate { get; set; }

    @AuraEnabled
    public List<MonthSummary> months { get; set; }

    @AuraEnabled
    public Decimal totalAmount { get; set; }

    @AuraEnabled
    public Integer totalSaleCount { get; set; }

    @AuraEnabled
    public Boolean hasSales { get; set; }
  }

  /**
   * One calendar month in the 12-month response.
   *
   * The LWC converts monthNumber into a localized month name using Intl,
   * allowing the component to work with English and Hebrew locales.
   */
  public class MonthSummary {
    @AuraEnabled
    public Integer year { get; set; }

    @AuraEnabled
    public Integer monthNumber { get; set; }

    @AuraEnabled
    public Decimal amount { get; set; }

    @AuraEnabled
    public Integer saleCount { get; set; }

    @AuraEnabled
    public Boolean hasSales { get; set; }
  }
}
