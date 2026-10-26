"======================================================================
" Transactional buffer
" Holds pending changes until RAP triggers the save sequence
"======================================================================
CLASS lcl_buffer DEFINITION FINAL.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_change,
        sales_order TYPE vbeln_va,
        reference   TYPE bstkd,
      END OF ty_change.

    TYPES tt_changes TYPE SORTED TABLE OF ty_change
                     WITH UNIQUE KEY sales_order.

    CLASS-DATA changes TYPE tt_changes.

    CLASS-METHODS is_authorized
      IMPORTING
        is_order          TYPE zi_rap_order
        iv_activity       TYPE activ_auth
      RETURNING
        VALUE(rv_allowed) TYPE abap_bool.

ENDCLASS.


CLASS lcl_buffer IMPLEMENTATION.

  METHOD is_authorized.

    rv_allowed = abap_false.

    AUTHORITY-CHECK OBJECT 'V_VBAK_VKO'
      ID 'VKORG' FIELD is_order-SalesOrganization
      ID 'VTWEG' FIELD is_order-DistributionChannel
      ID 'SPART' FIELD is_order-Division
      ID 'ACTVT' FIELD iv_activity.

    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    AUTHORITY-CHECK OBJECT 'V_VBAK_AAT'
      ID 'AUART' FIELD is_order-SalesOrderType
      ID 'ACTVT' FIELD iv_activity.

    rv_allowed = xsdbool( sy-subrc = 0 ).

  ENDMETHOD.

ENDCLASS.


"======================================================================
" Interaction-phase handler
"======================================================================
CLASS lhc_salesorder DEFINITION
  INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    METHODS get_instance_authorizations
      FOR INSTANCE AUTHORIZATION
      IMPORTING
        keys
        REQUEST requested_authorizations
        FOR salesorder
      RESULT result.

    METHODS update
      FOR MODIFY
      IMPORTING entities FOR UPDATE salesorder.

    METHODS read
      FOR READ
      IMPORTING keys FOR READ salesorder
      RESULT result.

    METHODS lock
      FOR LOCK
      IMPORTING keys FOR LOCK salesorder.

ENDCLASS.


CLASS lhc_salesorder IMPLEMENTATION.

  METHOD get_instance_authorizations.

    LOOP AT keys INTO DATA(ls_key).

      SELECT SINGLE *
        FROM zi_rap_order
        WHERE SalesOrder = @ls_key-SalesOrder
        INTO @DATA(ls_order).

      DATA(lv_allowed) = abap_false.

      IF sy-subrc = 0.

        lv_allowed = lcl_buffer=>is_authorized(
          is_order    = ls_order
          iv_activity = '02'
        ).

      ENDIF.

      APPEND VALUE #(
        SalesOrder = ls_key-SalesOrder

        %update = COND #(
          WHEN lv_allowed = abap_true
          THEN if_abap_behv=>auth-allowed
          ELSE if_abap_behv=>auth-unauthorized
        )
      ) TO result.

    ENDLOOP.

  ENDMETHOD.


  METHOD update.

    LOOP AT entities INTO DATA(ls_entity).

      "Only process an explicitly supplied customer reference.
      "An explicitly supplied empty value requests clearing the reference.
      IF ls_entity-%control-CustomerReference
           <> if_abap_behv=>mk-on.
        CONTINUE.
      ENDIF.

      SELECT SINGLE *
        FROM zi_rap_order
        WHERE SalesOrder = @ls_entity-SalesOrder
        INTO @DATA(ls_order).

      IF sy-subrc <> 0.

        APPEND VALUE #(
          SalesOrder  = ls_entity-SalesOrder
          %fail-cause = if_abap_behv=>cause-not_found
        ) TO failed-salesorder.

        APPEND VALUE #(
          SalesOrder = ls_entity-SalesOrder

          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'Sales order not found or not visible to this user.'
          )
        ) TO reported-salesorder.

        CONTINUE.

      ENDIF.

      "Explicit authorization check for the requested change.
      IF lcl_buffer=>is_authorized(
           is_order    = ls_order
           iv_activity = '02'
         ) = abap_false.

        APPEND VALUE #(
          SalesOrder  = ls_entity-SalesOrder
          %fail-cause = if_abap_behv=>cause-unauthorized
        ) TO failed-salesorder.

        APPEND VALUE #(
          SalesOrder = ls_entity-SalesOrder

          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'No authorization to change this sales order.'
          )
        ) TO reported-salesorder.

        CONTINUE.

      ENDIF.

      "Replace any previous pending value for the same order.
      DELETE TABLE lcl_buffer=>changes
        WITH TABLE KEY
          sales_order = ls_entity-SalesOrder.

      INSERT VALUE #(
        sales_order = ls_entity-SalesOrder
        reference   = ls_entity-CustomerReference
      ) INTO TABLE lcl_buffer=>changes.

      "Do not call the BAPI here.
      "This method only updates the transactional buffer.

    ENDLOOP.

  ENDMETHOD.


  METHOD read.

    LOOP AT keys INTO DATA(ls_key).

      SELECT SINGLE *
        FROM zi_rap_order
        WHERE SalesOrder = @ls_key-SalesOrder
        INTO @DATA(ls_order).

      IF sy-subrc <> 0.

        APPEND VALUE #(
          SalesOrder  = ls_key-SalesOrder
          %fail-cause = if_abap_behv=>cause-not_found
        ) TO failed-salesorder.

        CONTINUE.

      ENDIF.

      "Overlay pending changes within the current RAP transaction.
      READ TABLE lcl_buffer=>changes
        INTO DATA(ls_change)
        WITH TABLE KEY
          sales_order = ls_key-SalesOrder.

      IF sy-subrc = 0.
        ls_order-CustomerReference = ls_change-reference.
      ENDIF.

      APPEND CORRESPONDING #( ls_order ) TO result.

    ENDLOOP.

  ENDMETHOD.


  METHOD lock.

    LOOP AT keys INTO DATA(ls_key).

      "Check visibility before attempting the document lock.
      SELECT SINGLE SalesOrder
        FROM zi_rap_order
        WHERE SalesOrder = @ls_key-SalesOrder
        INTO @DATA(lv_order).

      IF sy-subrc <> 0.

        APPEND VALUE #(
          SalesOrder  = ls_key-SalesOrder
          %fail-cause = if_abap_behv=>cause-not_found
        ) TO failed-salesorder.

        CONTINUE.

      ENDIF.

      "Use the standard sales-order lock.
      CALL FUNCTION 'ENQUEUE_EVVBAKE'
        EXPORTING
          vbeln          = ls_key-SalesOrder
          _scope         = '2'
          _wait          = abap_false
        EXCEPTIONS
          foreign_lock   = 1
          system_failure = 2
          OTHERS         = 3.

      IF sy-subrc <> 0.

        APPEND VALUE #(
          SalesOrder  = ls_key-SalesOrder
          %fail-cause = if_abap_behv=>cause-locked
        ) TO failed-salesorder.

        APPEND VALUE #(
          SalesOrder = ls_key-SalesOrder

          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'Sales order is locked or the lock could not be obtained.'
          )
        ) TO reported-salesorder.

      ENDIF.

    ENDLOOP.

  ENDMETHOD.

ENDCLASS.


"======================================================================
" Save-phase implementation
" Special superclass permits reporting legacy BAPI errors in late save
"======================================================================
CLASS lsc_zi_rap_order DEFINITION
  INHERITING FROM cl_abap_behavior_saver_failed.

  PROTECTED SECTION.

    METHODS finalize          REDEFINITION.
    METHODS check_before_save REDEFINITION.
    METHODS save              REDEFINITION.
    METHODS cleanup           REDEFINITION.
    METHODS cleanup_finalize  REDEFINITION.

ENDCLASS.


CLASS lsc_zi_rap_order IMPLEMENTATION.

  METHOD finalize.

    "No final calculations are required for this increment.

  ENDMETHOD.


  METHOD check_before_save.

    "Restrict this prototype to one order per RAP transaction.
    IF lines( lcl_buffer=>changes ) > 1.

      LOOP AT lcl_buffer=>changes INTO DATA(ls_change).

        APPEND VALUE #(
          SalesOrder = ls_change-sales_order
        ) TO failed-salesorder.

        APPEND VALUE #(
          SalesOrder = ls_change-sales_order

          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'This prototype supports one order per transaction.'
          )
        ) TO reported-salesorder.

      ENDLOOP.

    ENDIF.

  ENDMETHOD.


  METHOD save.

    LOOP AT lcl_buffer=>changes INTO DATA(ls_change).

      "Call the existing BAPI wrapper only in the save phase.
      DATA(lt_return) =
        zcl_rap_order_api=>change_reference(
          iv_sales_order = ls_change-sales_order
          iv_reference   = ls_change-reference
        ).

      DATA(lv_has_error) = abap_false.

      LOOP AT lt_return INTO DATA(ls_return).

        IF ls_return-type = 'E'
           OR ls_return-type = 'A'
           OR ls_return-type = 'X'.

          lv_has_error = abap_true.

        ENDIF.

        IF ls_return-type = 'E'
           OR ls_return-type = 'A'
           OR ls_return-type = 'X'
           OR ls_return-type = 'W'.

          APPEND VALUE #(
            SalesOrder = ls_change-sales_order

            %msg = new_message_with_text(
              severity = COND #(
                WHEN ls_return-type = 'W'
                THEN if_abap_behv_message=>severity-warning
                ELSE if_abap_behv_message=>severity-error
              )

              text = CONV #( ls_return-message )
            )
          ) TO reported-salesorder.

        ENDIF.

      ENDLOOP.

      IF lv_has_error = abap_true.

        APPEND VALUE #(
          SalesOrder = ls_change-sales_order
        ) TO failed-salesorder.

        RETURN.

      ENDIF.

    ENDLOOP.

    "No explicit commit or rollback.
    "The RAP runtime owns transaction completion.

  ENDMETHOD.


  METHOD cleanup.

    CLEAR lcl_buffer=>changes.

  ENDMETHOD.


  METHOD cleanup_finalize.

    CLEAR lcl_buffer=>changes.

  ENDMETHOD.

ENDCLASS.
