@EndUserText.label: 'Sales Order - Unmanaged RAP'
@AccessControl.authorizationCheck: #CHECK
define root view entity ZI_RAP_Order
  as select from vbak as Header

    inner join vbkd as BusinessData
      on  BusinessData.vbeln = Header.vbeln
      and BusinessData.posnr = '000000'
{
  key Header.vbeln       as SalesOrder,

      Header.auart       as SalesOrderType,
      Header.vkorg       as SalesOrganization,
      Header.vtweg       as DistributionChannel,
      Header.spart       as Division,
      Header.kunnr       as SoldToParty,
      Header.audat       as SalesOrderDate,

      BusinessData.bstkd as CustomerReference
}
where
      Header.auart = 'TA'
  and Header.vkorg = '1710'
  and Header.vtweg = '10'
  and Header.spart = '10'
