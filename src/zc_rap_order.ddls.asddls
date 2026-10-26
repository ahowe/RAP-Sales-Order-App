@EndUserText.label: 'Sales Order'
@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true

define root view entity ZC_RAP_Order
  provider contract transactional_query
  as projection on ZI_RAP_Order
{
  key SalesOrder,

      SalesOrderType,
      SalesOrganization,
      DistributionChannel,
      Division,
      SoldToParty,
      SalesOrderDate,
      CustomerReference
}
