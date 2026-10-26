CLASS zcl_rap_order_api DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES tt_return TYPE STANDARD TABLE OF bapiret2
                    WITH DEFAULT KEY.

    CLASS-METHODS change_reference
      IMPORTING
        iv_sales_order   TYPE vbeln_va
        iv_reference     TYPE bstkd
      RETURNING
        VALUE(rt_return) TYPE tt_return.

ENDCLASS.


CLASS zcl_rap_order_api IMPLEMENTATION.

  METHOD change_reference.

    DATA ls_header  TYPE bapisdh1.
    DATA ls_headerx TYPE bapisdh1x.

    "New customer purchase-order reference
    ls_header-purch_no_c = iv_reference.

    "Update header and explicitly mark the changed field
    ls_headerx-updateflag = 'U'.
    ls_headerx-purch_no_c = 'X'.

    CALL FUNCTION 'BAPI_SALESORDER_CHANGE'
      EXPORTING
        salesdocument    = iv_sales_order
        order_header_in  = ls_header
        order_header_inx = ls_headerx
      TABLES
        return           = rt_return.

    "Do not commit or roll back here.
    "The RAP runtime will control the transaction.

  ENDMETHOD.

ENDCLASS.
