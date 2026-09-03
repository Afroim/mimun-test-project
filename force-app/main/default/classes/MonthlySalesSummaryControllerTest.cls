@IsTest
private class MonthlySalesSummaryControllerTest {
  private static final String SALES_REP_ALIAS = 'ssrep';
  private static final String SALES_MANAGER_ALIAS = 'ssmgr';

  @TestSetup
  static void setupUsersAndPermissions() {
    Profile standardUserProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];

    User currentUser = [
      SELECT TimeZoneSidKey
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ];

    String uniqueSuffix = String.valueOf(Datetime.now().getTime());

    User salesRepresentative = new User(
      FirstName = 'Sales',
      LastName = 'Representative',
      Alias = SALES_REP_ALIAS,
      Email = 'sales.representative@example.invalid',
      Username = 'sales.representative.' + uniqueSuffix + '@example.invalid',
      CommunityNickname = 'salesrep' + uniqueSuffix,
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = currentUser.TimeZoneSidKey,
      ProfileId = standardUserProfile.Id,
      IsActive = true
    );

    User salesManager = new User(
      FirstName = 'Sales',
      LastName = 'Manager',
      Alias = SALES_MANAGER_ALIAS,
      Email = 'sales.manager@example.invalid',
      Username = 'sales.manager.' + uniqueSuffix + '@example.invalid',
      CommunityNickname = 'salesmgr' + uniqueSuffix,
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = currentUser.TimeZoneSidKey,
      ProfileId = standardUserProfile.Id,
      IsActive = true
    );

    insert new List<User>{ salesRepresentative, salesManager };

    PermissionSet userPermissionSet = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'Sales_Summary_User'
      LIMIT 1
    ];

    PermissionSet managerPermissionSet = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'Sales_Summary_Manager'
      LIMIT 1
    ];

    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = salesRepresentative.Id,
        PermissionSetId = userPermissionSet.Id
      ),
      new PermissionSetAssignment(
        AssigneeId = salesManager.Id,
        PermissionSetId = userPermissionSet.Id
      ),
      new PermissionSetAssignment(
        AssigneeId = salesManager.Id,
        PermissionSetId = managerPermissionSet.Id
      )
    };
  }

  @IsTest
  static void regularUserReceivesOwnTwelveMonthSummary() {
    User salesRepresentative = getUserByAlias(SALES_REP_ALIAS);

    User salesManager = getUserByAlias(SALES_MANAGER_ALIAS);

    Account representativeAccount = new Account(
      Name = 'Representative Account',
      OwnerId = salesRepresentative.Id
    );

    Account managerAccount = new Account(
      Name = 'Manager Account',
      OwnerId = salesManager.Id
    );

    insert new List<Account>{ representativeAccount, managerAccount };

    Date currentMonth = Date.today().toStartOfMonth();

    Date startDate = currentMonth.addMonths(-11);

    insert new List<Sale__c>{
      createSale(
        representativeAccount.Id,
        salesRepresentative.Id,
        Date.today(),
        600
      ),
      createSale(
        representativeAccount.Id,
        salesRepresentative.Id,
        currentMonth.addDays(1),
        700
      ),
      createSale(
        representativeAccount.Id,
        salesRepresentative.Id,
        currentMonth.addMonths(-2).addDays(5),
        900
      ),
      createSale(
        representativeAccount.Id,
        salesRepresentative.Id,
        startDate.addDays(3),
        1200
      ),
      createSale(
        representativeAccount.Id,
        salesRepresentative.Id,
        startDate.addDays(-1),
        9999
      ),
      createSale(managerAccount.Id, salesManager.Id, Date.today(), 5000)
    };

    System.assertEquals(
      6,
      [
        SELECT COUNT()
        FROM Sale__c
      ],
      'Six test sales must be inserted.'
    );

    System.assertEquals(
      5,
      [
        SELECT COUNT()
        FROM Sale__c
        WHERE Account__r.OwnerId = :salesRepresentative.Id
      ],
      'Five sales must be associated with representative Accounts.'
    );

    Date endDateExclusive = currentMonth.addMonths(1);

    System.assertEquals(
      4,
      [
        SELECT COUNT()
        FROM Sale__c
        WHERE
          Account__r.OwnerId = :salesRepresentative.Id
          AND Sale_Date__c >= :startDate
          AND Sale_Date__c < :endDateExclusive
      ],
      'Four representative sales must be inside the twelve-month range.'
    );

    MonthlySalesSummaryController.SalesSummaryResponse response;

    System.runAs(salesRepresentative) {
      Test.startTest();

      response = MonthlySalesSummaryController.getSalesSummary(
        salesRepresentative.Id
      );

      Test.stopTest();
    }

    System.assertEquals(
      salesRepresentative.Id,
      response.salespersonId,
      'The response must belong to the requested salesperson.'
    );

    System.assertEquals(
      12,
      response.months.size(),
      'The response must contain exactly twelve months.'
    );

    System.assertEquals(
      startDate,
      response.startDate,
      'The range must start eleven months before the current month.'
    );

    System.assertEquals(
      currentMonth.addMonths(1).addDays(-1),
      response.endDate,
      'The range must end on the last day of the current month.'
    );

    System.assertEquals(
      Decimal.valueOf('3400'),
      response.totalAmount,
      'Only qualifying sales within the twelve-month range must be included.'
    );

    System.assertEquals(
      4,
      response.totalSaleCount,
      'Exactly four representative sales must be included.'
    );

    System.assertEquals(
      true,
      response.hasSales,
      'The response must indicate that sales exist.'
    );

    MonthlySalesSummaryController.MonthSummary currentMonthSummary = findMonth(
      response.months,
      currentMonth.year(),
      currentMonth.month()
    );

    System.assertEquals(
      Decimal.valueOf('1300'),
      currentMonthSummary.amount,
      'Current-month sales must be aggregated.'
    );

    System.assertEquals(
      2,
      currentMonthSummary.saleCount,
      'The current month must contain two sales.'
    );

    System.assertEquals(
      true,
      currentMonthSummary.hasSales,
      'The current month must indicate that sales exist.'
    );

    MonthlySalesSummaryController.MonthSummary firstMonthSummary = findMonth(
      response.months,
      startDate.year(),
      startDate.month()
    );

    System.assertEquals(
      Decimal.valueOf('1200'),
      firstMonthSummary.amount,
      'The first month in the range must be included.'
    );

    assertMonthsAreChronological(response.months, startDate);
  }

  @IsTest
  static void regularUserCannotViewAnotherSalesperson() {
    User salesRepresentative = getUserByAlias(SALES_REP_ALIAS);

    User salesManager = getUserByAlias(SALES_MANAGER_ALIAS);

    Boolean exceptionWasThrown = false;

    System.runAs(salesRepresentative) {
      Test.startTest();

      try {
        MonthlySalesSummaryController.getSalesSummary(salesManager.Id);
      } catch (AuraHandledException exceptionInstance) {
        exceptionWasThrown = true;
      }

      Test.stopTest();
    }

    System.assertEquals(
      true,
      exceptionWasThrown,
      'A regular user must not request another salesperson.'
    );
  }

  @IsTest
  static void managerCanViewAnotherSalesperson() {
    User salesRepresentative = getUserByAlias(SALES_REP_ALIAS);

    User salesManager = getUserByAlias(SALES_MANAGER_ALIAS);

    Account representativeAccount = new Account(
      Name = 'Manager Test Account',
      OwnerId = salesRepresentative.Id
    );

    insert representativeAccount;

    /*
     * The Sale record owner is deliberately the manager,
     * while the related Account owner is the representative.
     *
     * The result must be assigned according to Account.OwnerId,
     * not Sale__c.OwnerId.
     */
    insert createSale(
      representativeAccount.Id,
      salesManager.Id,
      Date.today(),
      1500
    );

    MonthlySalesSummaryController.SalesSummaryResponse response;

    System.runAs(salesManager) {
      Test.startTest();

      response = MonthlySalesSummaryController.getSalesSummary(
        salesRepresentative.Id
      );

      Test.stopTest();
    }

    System.assertEquals(
      salesRepresentative.Id,
      response.salespersonId,
      'The manager must be able to select another active salesperson.'
    );

    System.assertEquals(
      Decimal.valueOf('1500'),
      response.totalAmount,
      'The manager must receive the selected salesperson sales.'
    );

    System.assertEquals(
      1,
      response.totalSaleCount,
      'One sale must be returned.'
    );

    System.assertEquals(
      true,
      response.hasSales,
      'The response must indicate that sales exist.'
    );
  }

  @IsTest
  static void responseContainsNoSalesWhenPeriodIsEmpty() {
    User salesRepresentative = getUserByAlias(SALES_REP_ALIAS);

    MonthlySalesSummaryController.SalesSummaryResponse response;

    System.runAs(salesRepresentative) {
      Test.startTest();

      response = MonthlySalesSummaryController.getSalesSummary(null);

      Test.stopTest();
    }

    System.assertEquals(
      salesRepresentative.Id,
      response.salespersonId,
      'A null salesperson must default to the current user.'
    );

    System.assertEquals(
      12,
      response.months.size(),
      'The controller must still produce twelve month entries.'
    );

    System.assertEquals(
      Decimal.valueOf('0'),
      response.totalAmount,
      'The total must be zero when no sales exist.'
    );

    System.assertEquals(
      0,
      response.totalSaleCount,
      'The total sale count must be zero.'
    );

    System.assertEquals(
      false,
      response.hasSales,
      'The LWC must be instructed to show a toast and hide the table.'
    );

    for (
      MonthlySalesSummaryController.MonthSummary monthSummary : response.months
    ) {
      System.assertEquals(
        Decimal.valueOf('0'),
        monthSummary.amount,
        'An empty month must have a zero amount.'
      );

      System.assertEquals(
        0,
        monthSummary.saleCount,
        'An empty month must have a zero sale count.'
      );

      System.assertEquals(
        false,
        monthSummary.hasSales,
        'An empty month must not be marked as containing sales.'
      );
    }
  }

  @IsTest
  static void historicalSaleBelongsToCurrentAccountOwner() {
    User salesRepresentative = getUserByAlias(SALES_REP_ALIAS);

    User salesManager = getUserByAlias(SALES_MANAGER_ALIAS);

    Account transferredAccount = new Account(
      Name = 'Transferred Account',
      OwnerId = salesRepresentative.Id
    );

    insert transferredAccount;

    /*
     * Sale ownership is intentionally independent of Account ownership.
     */
    insert createSale(
      transferredAccount.Id,
      salesManager.Id,
      Date.today(),
      750
    );

    transferredAccount.OwnerId = salesManager.Id;
    update transferredAccount;

    MonthlySalesSummaryController.SalesSummaryResponse representativeResponse;

    MonthlySalesSummaryController.SalesSummaryResponse managerResponse;

    System.runAs(salesManager) {
      Test.startTest();

      representativeResponse = MonthlySalesSummaryController.getSalesSummary(
        salesRepresentative.Id
      );

      managerResponse = MonthlySalesSummaryController.getSalesSummary(
        salesManager.Id
      );

      Test.stopTest();
    }

    System.assertEquals(
      false,
      representativeResponse.hasSales,
      'The previous Account owner must not receive the historical sale.'
    );

    System.assertEquals(
      Decimal.valueOf('0'),
      representativeResponse.totalAmount,
      'The previous Account owner total must be zero.'
    );

    System.assertEquals(
      true,
      managerResponse.hasSales,
      'The sale must belong to the current Account owner.'
    );

    System.assertEquals(
      Decimal.valueOf('750'),
      managerResponse.totalAmount,
      'Historical sales must follow the current Account owner.'
    );
  }

  private static User getUserByAlias(String userAlias) {
    return [
      SELECT Id, Alias, IsActive
      FROM User
      WHERE Alias = :userAlias
      LIMIT 1
    ];
  }

  private static Sale__c createSale(
    Id accountId,
    Id saleOwnerId,
    Date saleDate,
    Decimal amount
  ) {
    return new Sale__c(
      OwnerId = saleOwnerId,
      Account__c = accountId,
      Sale_Date__c = saleDate,
      Amount__c = amount
    );
  }

  private static MonthlySalesSummaryController.MonthSummary findMonth(
    List<MonthlySalesSummaryController.MonthSummary> months,
    Integer year,
    Integer monthNumber
  ) {
    for (MonthlySalesSummaryController.MonthSummary monthSummary : months) {
      if (
        monthSummary.year == year &&
        monthSummary.monthNumber == monthNumber
      ) {
        return monthSummary;
      }
    }

    System.assert(
      false,
      'Expected month was not found: ' + year + '-' + monthNumber
    );

    return null;
  }

  private static void assertMonthsAreChronological(
    List<MonthlySalesSummaryController.MonthSummary> months,
    Date expectedStartDate
  ) {
    for (Integer index = 0; index < months.size(); index++) {
      Date expectedMonth = expectedStartDate.addMonths(index);

      System.assertEquals(
        expectedMonth.year(),
        months[index].year,
        'Unexpected year at month index ' + index + '.'
      );

      System.assertEquals(
        expectedMonth.month(),
        months[index].monthNumber,
        'Unexpected month number at index ' + index + '.'
      );
    }
  }
}
