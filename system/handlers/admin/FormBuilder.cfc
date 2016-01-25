component extends="preside.system.base.AdminHandler" {

	property name="formBuilderService"          inject="formBuilderService";
	property name="formBuilderRenderingService" inject="formBuilderRenderingService";
	property name="itemTypesService"            inject="formBuilderItemTypesService";
	property name="messagebox"                  inject="coldbox:plugin:messagebox";


// PRE-HANDLER
	public void function preHandler( event, action, eventArguments ) {
		super.preHandler( argumentCollection = arguments );

		if ( !isFeatureEnabled( "formbuilder" ) ) {
			event.notFound();
		}

		_permissionsCheck( "navigate", event );

		event.addAdminBreadCrumb(
			  title = translateResource( "formbuilder:breadcrumb.title" )
			, link  = event.buildAdminLink( linkTo="formbuilder" )
		);
		prc.pageIcon = "check-square-o";
	}

// DEFACTO PUBLIC ACTIONS
	public void function index( event, rc, prc ) {
		prc.pageTitle    = translateResource( "formbuilder:page.title" );
		prc.pageSubtitle = translateResource( "formbuilder:page.subtitle" );

		prc.canAdd = hasCmsPermission( permissionKey="formbuilder.addform" );
	}

	public void function addForm( event, rc, prc ) {
		_permissionsCheck( "addform", event );

		prc.pageTitle    = translateResource( "formbuilder:add.form.page.title" );
		prc.pageSubtitle = translateResource( "formbuilder:add.form.page.subtitle" );

		event.addAdminBreadCrumb(
			  title = translateResource( "formbuilder:addform.breadcrumb.title" )
			, link  = event.buildAdminLink( linkTo="formbuilder.addform" )
		);
	}

	public void function manageForm( event, rc, prc ) {
		prc.form = formBuilderService.getForm( rc.id ?: "" );

		if ( !prc.form.recordcount ) {
			messagebox.error( translateResource( "formbuilder:form.not.found.alert" ) );
			setNextEvent( url=event.buildAdminLink( "formbuilder" ) );
		}

		if ( IsTrue( prc.form.locked ) ) {
			setNextEvent( url=event.buildAdminLink( linkTo="formbuilder.submissions", queryString="id=" & prc.form.id ) );
		}

		prc.pageTitle    = prc.form.name;
		prc.pageSubtitle = prc.form.description;

		event.addAdminBreadCrumb(
			  title = translateResource( uri="formbuilder:manageform.breadcrumb.title", data=[ prc.form.name ] )
			, link  = event.buildAdminLink( linkTo="formbuilder.manageform", queryString="id=" & prc.form.id )
		);

		event.includeData( {
			  "formbuilderFormId"               = prc.form.id
			, "formbuilderSaveNewItemEndpoint"  = event.buildAdminLink( linkTo="formbuilder.addItemAction" )
			, "formbuilderDeleteItemEndpoint"   = event.buildAdminLink( linkTo="formbuilder.deleteItemAction" )
			, "formbuilderSaveItemEndpoint"     = event.buildAdminLink( linkTo="formbuilder.saveItemAction" )
			, "formbuilderSetSortOrderEndpoint" = event.buildAdminLink( linkTo="formbuilder.setSortOrderAction" )
		} );
	}

	public void function itemConfigDialog( event, rc, prc ) {
		if ( Len( Trim( rc.itemId ?: "" ) ) ) {
			var item = formBuilderService.getFormItem( rc.itemId );
			if ( item.count() ) {
				prc.savedData = item.configuration;
			}
		}

		prc.itemTypeConfig = itemTypesService.getItemTypeConfig( rc.itemType ?: "" );
		prc.pageTitle      = translateResource( uri="formbuilder:itemconfig.dialog.title"   , data=[ prc.itemTypeConfig.title ] );
		prc.pageSubTitle   = translateResource( uri="formbuilder:itemconfig.dialog.subtitle", data=[ prc.itemTypeConfig.title ] );
		prc.pageIcon       = "cog";

		if ( !prc.itemTypeConfig.count() ) {
			event.adminNotFound();
		}

		event.setLayout( "adminModalDialog" );

		event.includeData( {
			"formBuilderValidationEndpoint" = event.buildAdminLink( linkTo="formbuilder.validateItemConfig" )
		} );
	}

	public void function validateItemConfig( event, rc, prc ) {
		var config = event.getCollectionWithoutSystemVars();

		config.delete( "formId"   );
		config.delete( "itemId"   );
		config.delete( "itemType" );

		var validationResult = formBuilderService.validateItemConfig(
			  formId    = rc.formId   ?: ""
			, itemId    = rc.itemId   ?: ""
			, itemType  = rc.itemType ?: ""
			, config    = config
		);

		if ( validationResult.validated() ) {
			event.renderData( data=true, type="json" );
		} else {
			var errors = {};
			var messages = validationResult.getMessages();

			for( var fieldName in messages ){
				errors[ fieldName ] = translateResource( uri=messages[ fieldName ].message, defaultValue=messages[ fieldName ].message, data=messages[ fieldName ].params ?: [] );
			}
			event.renderData( data=errors, type="json" );
		}
	}

	public void function submissions( event, rc, prc ) {
		prc.form = formBuilderService.getForm( rc.id ?: "" );

		if ( !prc.form.recordcount ) {
			messagebox.error( translateResource( "formbuilder:form.not.found.alert" ) );
			setNextEvent( url=event.buildAdminLink( "formbuilder" ) );
		}

		prc.pageTitle    = prc.form.name;
		prc.pageSubtitle = prc.form.description;

		event.addAdminBreadCrumb(
			  title = translateResource( uri="formbuilder:manageform.breadcrumb.title", data=[ prc.form.name ] )
			, link  = event.buildAdminLink( linkTo="formbuilder.manageform", queryString="id=" & prc.form.id )
		);
		event.addAdminBreadCrumb(
			  title = translateResource( uri="formbuilder:submissions.breadcrumb.title", data=[ prc.form.name ] )
			, link  = event.buildAdminLink( linkTo="formbuilder.submissions", queryStrign="id=" & prc.form.id )
		);

	}

	public void function editForm( event, rc, prc ) {
		_permissionsCheck( "editform", event );

		prc.form = formBuilderService.getForm( rc.id ?: "" );

		if ( !prc.form.recordcount ) {
			messagebox.error( translateResource( "formbuilder:form.not.found.alert" ) );
			setNextEvent( url=event.buildAdminLink( "formbuilder" ) );
		}
		if ( IsTrue( prc.form.locked ) ) {
			setNextEvent( url=event.buildAdminLink( linkTo="formbuilder.submissions", queryString="id=" & prc.form.id ) );
		}

		prc.form = QueryRowToStruct( prc.form );

		prc.pageTitle    = translateResource( uri="formbuilder:edit.form.page.title"   , data=[ prc.form.name ] );
		prc.canEdit      = hasCmsPermission( permissionKey="formbuilder.editform" );

		event.addAdminBreadCrumb(
			  title = translateResource( uri="formbuilder:manageform.breadcrumb.title", data=[ prc.form.name ] )
			, link  = event.buildAdminLink( linkTo="formbuilder.manageform", queryString="id=" & prc.form.id )
		);
		event.addAdminBreadCrumb(
			  title = translateResource( uri="formbuilder:edit.form.breadcrumb.title", data=[ prc.form.name ] )
			, link  = event.buildAdminLink( linkTo="formbuilder.editform", queryStrign="id=" & prc.form.id )
		);
	}



// DOING STUFF ACTIONS
	public void function addFormAction( event, rc, prc ) {
		_permissionsCheck( "addform", event );

		runEvent(
			  event          = "admin.DataManager._addRecordAction"
			, prePostExempt  = true
			, private        = true
			, eventArguments = {
				  object           = "formbuilder_form"
				, errorAction      = "formbuilder.addform"
				, successAction    = "formbuilder.manageform"
				, addAnotherAction = "formbuilder.addform"
				, viewRecordAction = "formbuilder.manageform"
			}
		);
	}

	public void function editFormAction( event, rc, prc ) {
		_permissionsCheck( "editform", event );
		var formId = rc.id ?: "";
		if ( formBuilderService.isFormLocked( formId ) ) {
			event.adminAccessDenied();
		}

		runEvent(
			  event          = "admin.DataManager._editRecordAction"
			, prePostExempt  = true
			, private        = true
			, eventArguments = {
				  object           = "formbuilder_form"
				, errorUrl         = event.buildAdminLink( linkTo="formbuilder.editform", queryString="id=" & formId )
				, successUrl       = event.buildAdminLink( linkTo="formbuilder.manageform", queryString="id=" & formId )
			}
		);
	}

	public void function addItemAction( event, rc, prc ) {
		var configuration = event.getCollectionWithoutSystemVars();

		configuration.delete( "formId"   );
		configuration.delete( "itemType" );

		var newId = formBuilderService.addItem(
			  formId        = rc.formId   ?: ""
			, itemType      = rc.itemType ?: ""
			, configuration = configuration
		);

		event.renderData( type="json", data={
			  id       = newId
			, itemView = renderViewlet( event="admin.formbuilder.workbenchFormItem", args=formBuilderService.getFormItem( newId ) )
		} );
	}

	public void function saveItemAction( event, rc, prc ) {
		var configuration = event.getCollectionWithoutSystemVars();
		var itemId        = rc.id ?: "";

		configuration.delete( "id" );

		formBuilderService.saveItem(
			  id            = itemId
			, configuration = configuration
		);

		event.renderData( type="json", data={
			  id       = itemId
			, itemView = renderViewlet( event="admin.formbuilder.workbenchFormItem", args=formBuilderService.getFormItem( itemId ) )
		} );
	}

	public void function deleteItemAction( event, rc, prc ) {
		var deleteSuccess = formBuilderService.deleteItem( rc.id ?: "" );

		event.renderData( data=deleteSuccess, type="json" );
	}

	public void function setSortOrderAction( event, rc, prc ) {
		var itemsUpdated = formBuilderService.setItemsSortOrder( ListToArray( rc.itemIds ?: "" ) );
		var success      = itemsUpdated > 0;

		event.renderData( data=success, type="json" );
	}

	public void function activateAction( event, rc, prc ) {
		_permissionsCheck( "activateForm", event );

		var formId    = rc.id ?: "";
		var activated = IsTrue( rc.activated ?: "" );

		if ( formBuilderService.isFormLocked( formId ) ) {
			event.adminAccessDenied();
		}

		if ( activated ) {
			formBuilderService.activateForm( formId );
			messagebox.info( translateResource( "formbuilder:activated.confirmation" ) );
		} else {
			formBuilderService.deactivateForm( formId );
			messagebox.info( translateResource( "formbuilder:deactivated.confirmation" ) );
		}

		setNextEvent( url=event.buildAdminLink( linkTo="formbuilder.manageform", querystring="id=" & formId ) )
	}

	public void function lockAction( event, rc, prc ) {
		_permissionsCheck( "lockForm", event );

		var formId = rc.id ?: "";
		var locked = IsTrue( rc.locked ?: "" );

		if ( locked ) {
			formBuilderService.lockForm( formId );
			messagebox.info( translateResource( "formbuilder:locked.confirmation" ) );
		} else {
			formBuilderService.unlockForm( formId );
			messagebox.info( translateResource( "formbuilder:unlocked.confirmation" ) );
		}

		setNextEvent( url=event.buildAdminLink( linkTo="formbuilder.manageform", querystring="id=" & formId ) )

	}


// AJAXY ACTIONS
	public void function getFormsForAjaxDataTables( event, rc, prc ) {
		runEvent(
			  event          = "admin.DataManager._getObjectRecordsForAjaxDataTables"
			, prePostExempt  = true
			, private        = true
			, eventArguments = {
				  object          = "formbuilder_form"
				, useMultiActions = false
				, gridFields      = "name,description,locked,active,active_from,active_to"
				, actionsView     = "admin.formbuilder.formDataTableGridFields"
			}
		);
	}

	public void function listSubmissionsForAjaxDataTable( event, rc, prc ) {
		var formId   = ( rc.formId ?: "" );

		if ( !Len( Trim( formId ) ) ) {
			event.adminNotFound();
		}
		var canDelete       = hasCmsPermission( "formbuilder.deleteSubmissions" );
		var useMultiActions = canDelete;
		var checkboxCol     = [];
		var optionsCol      = [];
		var gridFields      = [ "submitted_by", "datecreated", "form_instance", "submitted_data" ];
		var dtHelper        = getMyPlugin( "JQueryDatatablesHelpers" );
		var results         = formbuilderService.getSubmissionsForGridListing(
			  formId      = formId
			, startRow    = dtHelper.getStartRow()
			, maxRows     = dtHelper.getMaxRows()
			, orderBy     = dtHelper.getSortOrder()
			, searchQuery = dtHelper.getSearchQuery()
		);
		var records = Duplicate( results.records );
		var deleteSubmissionTitle = translateResource( "formbuilder:delete.submission.prompt")

		for( var record in records ){
			for( var field in gridFields ){
				records[ field ][ records.currentRow ] = renderField( "formbuilder_formsubmission", field, record[ field ], [ "adminDataTable", "admin" ] );
			}

			if ( useMultiActions ) {
				checkboxCol.append( renderView( view="/admin/datamanager/_listingCheckbox", args={ recordId=record.id } ) );
			}

			optionsCol.append( renderView( view="/admin/formbuilder/_submissionActions", args={
				  canDelete             = canDelete
				, viewSubmissionLink    = event.buildAdminLink( linkto="formbuilder.viewSubmission"         , queryString="id=#record.id#" )
				, deleteSubmissionLink  = event.buildAdminLink( linkto="formbuilder.deleteSubmissionsAction", queryString="id=#record.id#&formId=#formId#" )
				, deleteSubmissionTitle = deleteSubmissionTitle
 			} ) );
		}

		if ( useMultiActions ) {
			QueryAddColumn( records, "_checkbox", checkboxCol );
			ArrayPrepend( gridFields, "_checkbox" );
		}

		QueryAddColumn( records, "_options" , optionsCol );
		ArrayAppend( gridFields, "_options" );

		event.renderData(
			  type = "json"
			, data = dtHelper.queryToResult( records, gridFields, results.totalRecords )
		);
	}

// VIEWLETS
	private string function formDataTableGridFields( event, rc, prc, args ) {
		args.canEdit = hasCmsPermission( permissionKey="formbuilder.editform" );

		return renderView( view="/admin/formbuilder/_formGridFields", args=args );
	}

	private string function itemTypePicker( event, rc, prc, args ) {
		args.itemTypesByCategory = itemTypesService.getItemTypesByCategory();

		return renderView( view="/admin/formbuilder/_itemTypePicker", args=args );
	}

	private string function itemsManagement( event, rc, prc, args ) {
		args.items = formBuilderService.getFormItems( args.formId ?: "" );
		return renderView( view="/admin/formbuilder/_itemsManagement", args=args );
	}

	private string function managementTabs( event, rc, prc, args ) {
		var formId   = rc.id ?: "";
		var isLocked = formBuilderService.isFormLocked( formId );

		args.canEdit         = !isLocked && hasCmsPermission( permissionKey="formbuilder.editform" );
		args.submissionCount = formBuilderService.getSubmissionCount( formId );

		return renderView( view="/admin/formbuilder/_managementTabs", args=args );
	}

	private string function statusControls( event, rc, prc, args ) {
		args.locked      = IsTrue( args.locked ?: "" );
		args.canLock     = hasCmsPermission( permissionKey="formbuilder.lockForm" );
		args.canActivate = !args.locked && hasCmsPermission( permissionKey="formbuilder.activateForm" );

		return renderView( view="/admin/formbuilder/_statusControls", args=args );
	}

	private string function workbenchFormItem( event, rc, prc, args ) {
		args.placeholder = renderViewlet(
			  event = formBuilderRenderingService.getItemTypeViewlet( itemType=( args.type.id ?: "" ), context="adminPlaceholder" )
			, args  = args
		);
		return renderView( view="/admin/formbuilder/_workbenchFormItem", args=args );
	}

// PRIVATE UTILITY
	private void function _permissionsCheck( required string key, required any event ) {
		var permKey   = "formbuilder." & arguments.key;
		var permitted = hasCmsPermission( permissionKey=permKey );

		if ( !permitted ) {
			event.adminAccessDenied();
		}
	}
}