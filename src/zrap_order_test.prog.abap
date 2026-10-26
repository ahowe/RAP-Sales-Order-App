REPORT zrap_order_test.

PARAMETERS:
  p_order TYPE vbeln_va OBLIGATORY,
  p_ref   TYPE bstkd OBLIGATORY.


START-OF-SELECTION.

  "------------------------------------------------------------
  " 1. Read the existing order through RAP
  "------------------------------------------------------------
  READ ENTITIES OF ZI_RAP_Order
    ENTITY SalesOrder
      ALL FIELDS
      WITH VALUE #(
        ( SalesOrder = p_order )
      )
    RESULT DATA(lt_before)
    FAILED DATA(ls_read_failed)
    REPORTED DATA(ls_read_reported).

  LOOP AT ls_read_reported-SalesOrder
    INTO DATA(ls_read_message).

    IF ls_read_message-%msg IS BOUND.
      WRITE: / ls_read_message-%msg->if_message~get_text( ).
    ENDIF.

  ENDLOOP.

  IF ls_read_failed IS NOT INITIAL
     OR lt_before IS INITIAL.

    WRITE: / 'Order not found or not visible to this user.'.
    ROLLBACK ENTITIES.
    RETURN.

  ENDIF.

  WRITE:
    / 'Sales order:', p_order,
    / 'Original reference:', lt_before[ 1 ]-CustomerReference,
    / 'Requested reference:', p_ref.

  "------------------------------------------------------------
  " 2. Request the customer-reference update through RAP
  "------------------------------------------------------------
  MODIFY ENTITIES OF ZI_RAP_Order
    ENTITY SalesOrder
      UPDATE FIELDS ( CustomerReference )
      WITH VALUE #(
        (
          SalesOrder        = p_order
          CustomerReference = p_ref
        )
      )
    FAILED DATA(ls_modify_failed)
    REPORTED DATA(ls_modify_reported).

  LOOP AT ls_modify_reported-SalesOrder
    INTO DATA(ls_modify_message).

    IF ls_modify_message-%msg IS BOUND.
      WRITE: / ls_modify_message-%msg->if_message~get_text( ).
    ENDIF.

  ENDLOOP.

  IF ls_modify_failed IS NOT INITIAL.

    WRITE: / 'Update rejected during the interaction phase.'.
    ROLLBACK ENTITIES.
    RETURN.

  ENDIF.

  "------------------------------------------------------------
  " 3. Read again before saving
  "    This should return the pending value from our buffer
  "------------------------------------------------------------
  READ ENTITIES OF ZI_RAP_Order
    ENTITY SalesOrder
      FIELDS ( CustomerReference )
      WITH VALUE #(
        ( SalesOrder = p_order )
      )
    RESULT DATA(lt_pending)
    FAILED DATA(ls_pending_failed)
    REPORTED DATA(ls_pending_reported).

  IF ls_pending_failed IS NOT INITIAL
     OR lt_pending IS INITIAL.

    WRITE: / 'Could not read the pending change.'.
    ROLLBACK ENTITIES.
    RETURN.

  ENDIF.

  IF lt_pending[ 1 ]-CustomerReference <> p_ref.

    WRITE: / 'Buffer verification failed. No change saved.'.
    ROLLBACK ENTITIES.
    RETURN.

  ENDIF.

  WRITE:
    / 'Pending reference:', lt_pending[ 1 ]-CustomerReference,
    / 'Buffer verification passed.'.

  "------------------------------------------------------------
  " 4. Trigger the RAP save sequence
  "    The saver calls our BAPI wrapper
  "------------------------------------------------------------
  COMMIT ENTITIES RESPONSE OF ZI_RAP_Order
    FAILED DATA(ls_save_failed)
    REPORTED DATA(ls_save_reported).

  "Capture immediately before another statement changes SY-SUBRC.
  DATA(lv_save_subrc) = sy-subrc.

  LOOP AT ls_save_reported-SalesOrder
    INTO DATA(ls_save_message).

    IF ls_save_message-%msg IS BOUND.
      WRITE: / ls_save_message-%msg->if_message~get_text( ).
    ENDIF.

  ENDLOOP.

  IF lv_save_subrc <> 0
     OR ls_save_failed IS NOT INITIAL.

    WRITE:
      / 'RAP save failed.',
      / 'Save return code:', lv_save_subrc.

    ROLLBACK ENTITIES.
    RETURN.

  ENDIF.

  WRITE:
    / 'RAP save sequence completed without a reported failure.',
    / 'Verify the saved customer reference in VA03.'.
