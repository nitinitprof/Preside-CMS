/**
 * Service responsible for the business logic of running ad-hoc tasks
 *
 * @singleton
 * @presideService
 * @autodoc
 *
 */
component displayName="Ad-hoc Task Manager Service" {

// CONSTRUCTOR
	/**
	 * @taskScheduler.inject taskScheduler
	 * @siteService.inject   siteService
	 * @logger.inject        logbox:logger:taskmanager
	 */
	public any function init(
		  required any     taskScheduler
		, required any     siteService
		, required any     logger
		,          numeric maxTaskTimeout = ( 60 * 60 * 24 * 365 ) // one year!
	) {
		_setTaskScheduler( arguments.taskScheduler );
		_setSiteService( arguments.siteService );
		_setLogger( arguments.logger );
		_setMaxTimeout( arguments.maxTaskTimeout );

		return this;
	}

// PUBLIC API METHODS
	/**
	 * Registers a new task, optionally running it there and then
	 * in a background thread
	 *
	 * @autodoc           true
	 * @event             Coldbox event that will be run
	 * @args              Args struct to pass to the coldbox event
	 * @adminOwner        Optional admin user ID, owner of the task
	 * @adminOwner        Optional admin user ID, owner of the task
	 * @webOwner          Optional website user ID, owner of the task
	 * @discardOnComplete Whether or not to discard the task once completed or permanently failed.
	 * @retryInterval     Definition of retry attempts for tasks that fail to run. Either a single struct, or array of structs with the following keys: `tries`: number of attempts, `interval`:number in seconds between tries (can also use CreateTimeSpan()). For example: `[ { tries:3, interval=CreateTimeSpan( 0, 0, 5, 0 ) }, { tries:2, interval=3600 }]` will retry three times with 5 minutes between attempts and then retry a further two times with 60 minutes between attempts.
	 * @title             Optional title of the task, can be an i18n resource URI for later translation. This will be used in any task progress UIs, etc.
	 * @titleData         Optional array of strings that will be passed into translateResource() along with title URI to create translatable title
	 * @resultUrl         Optional URL at which the result of this task can be viewed / downloaded. The token, `{taskId}`, within the URL will be replaced with the actual ID of the task
	 * @returnUrl         Optional URL to which to direct users from core admin UIs when they have finished with viewing a task
	 */
	public string function createTask(
		  required string  event
		,          struct  args              = {}
		,          string  adminOwner        = ""
		,          string  webOwner          = ""
		,          boolean runNow            = false
		,          boolean discardOnComplete = false
		,          any     retryInterval     = []
		,          string  title             = ""
		,          array   titleData         = []
		,          string  resultUrl         = ""
		,          string  returnUrl         = ""
	) {
		var taskId = $getPresideObject( "taskmanager_adhoc_task" ).insertData( {
			  event               = arguments.event
			, event_args          = SerializeJson( arguments.args )
			, admin_owner         = arguments.adminOwner
			, web_owner           = arguments.webOwner
			, discard_on_complete = arguments.discardOnComplete
			, retry_interval      = _serializeRetryInterval( arguments.retryInterval )
			, title               = arguments.title
			, title_data          = SerializeJson( arguments.titleData )
			, result_url          = arguments.resultUrl
			, return_url          = arguments.returnUrl
		} );

		if ( arguments.resultUrl.findNoCase( "{taskId}" ) ) {
			setResultUrl( taskId=taskId, resultUrl=arguments.resultUrl.replaceNoCase( "{taskId}", taskId, "all" ) );
		}

		if ( arguments.runNow ) {
			runTaskInThread( taskId=taskId );
		}

		return taskId;
	}

	/**
	 * Runs a registered task
	 *
	 * @autodoc true
	 * @taskId  ID of the task to run
	 */
	public boolean function runTask( required string taskId ) {
		lock timeout="1" name="adhocRunTask#arguments.taskId#" {
			var task  = getTask( arguments.taskId );
			var event = task.event ?: "";
			var args  = IsJson( task.event_args ?: "" ) ? DeserializeJson( task.event_args ) : {};
			var e     = "";

			if ( task.status == "running" ) {
				$raiseError( error={
					  type    = "AdHoTaskManagerService.task.already.running"
					, message = "Task not run. The task with ID, [#arguments.taskId#], is already running."
				} );

				return false;
			}

			markTaskAsRunning( taskId=arguments.taskId );
			/*
			$getPresideObject( "taskmanager_adhoc_task" ).updateData(
				  id   = arguments.taskId
				, data = { status="running" }
			);*/

			try {
				$getColdbox().runEvent(
					  event          = task.event
					, eventArguments = { args=args, logger=_getTaskLogger( taskId ), progress=_getTaskProgressReporter( taskId ) }
					, private        = true
					, prepostExempt  = true
				);
			} catch( any e ) {
				failTask( taskId=arguments.taskId, error=e );
				$raiseError( error=e );
				return false;
			}

			completeTask( taskId=arguments.taskId );
		}

		return true;
	}

	/**
	 * Runs the task in a background thread
	 *
	 * @autodoc true
	 * @taskId  ID of the task to run
	 */
	public void function runTaskInThread( required string taskId ) {
		if ( _inChildThread() ) {
			runTask( arguments.taskId );
		}

		thread action="run" name="runTask-#CreateUUId()#" taskId=arguments.taskId {
			setting requesttimeout=_getMaxTimeout();
			runTask( taskId=attributes.taskId );
		}
	}

	/**
	 * Gets the database record for the given task ID
	 *
	 * @autodoc true
	 * @taskId  ID of the task to get
	 */
	public query function getTask( required string taskId ) {
		return $getPresideObject( "taskmanager_adhoc_task" ).selectData( id=arguments.taskId );
	}

	/**
	 * Marks a task as running and resets running date, log, stats, etc.
	 *
	 * @autodoc true
	 * @taskId  ID of the task to mark as running
	 */
	public void function markTaskAsRunning( required string taskId ) {
		$getPresideObject( "taskmanager_adhoc_task" ).updateData(
			  id   = arguments.taskId
			, data = {
				  status              = "running"
				, started_on          = _now()
				, progress_percentage = 0
				, log                 = ""
				, next_attempt_date   = ""
				, finished_on         = ""
			  }
		);
	}

	/**
	 * Marks a task as complete
	 *
	 * @autodoc true
	 * @taskId ID of the task to mark as complete
	 */
	public void function completeTask( required string taskId ) {
		var task = getTask( arguments.taskId );

		if ( IsBoolean( task.discard_on_complete ?: "" ) && task.discard_on_complete ) {
			discardTask( taskId=arguments.taskId );
			return;
		}

		$getPresideObject( "taskmanager_adhoc_task" ).updateData(
			  id   = arguments.taskId
			, data = { status="succeeded", finished_on=_now() }
		);
	}

	/**
	 * Marks a task as failed
	 *
	 * @autodoc true
	 * @taskId  ID of the task to mark as failed
	 * @error   Error that prompted task failure
	 */
	public void function failTask( required string taskId, struct error={} ) {
		var nextAttempt = getNextAttemptInfo( arguments.taskId );

		if ( IsDate( nextAttempt.nextAttemptDate ) ) {
			requeueTask(
				  taskId          = arguments.taskId
				, error           = arguments.error
				, attemptCount    = nextAttempt.totalAttempts
				, nextAttemptDate = nextAttempt.nextAttemptDate
			);

			return;
		}

		$getPresideObject( "taskmanager_adhoc_task" ).updateData(
			  id   = arguments.taskId
			, data = {
				  status        = "failed"
				, last_error    = SerializeJson( arguments.error )
				, attempt_count = nextAttempt.totalAttempts
				, finished_on   = _now()
			  }
		);
	}

	/**
	 * Requeues a task for execution
	 *
	 * @autodoc         true
	 * @taskId          ID of the task to re-queue
	 * @error           Error that prompted requeue (see failtask())
	 * @attemptCount    Number of attempts made so far
	 * @nextAttemptDate Date of next attempt
	 */
	public void function requeueTask(
		  required string  taskId
		, required date    nextAttemptDate
		,          any     error = {}
		,          numeric attemptCount = 1
	) {
		var scheduleSettings = $getPresideCategorySettings( category="taskmanager" );

		_getTaskScheduler().createTask(
			  task          = "PresideAdHocTask-" & arguments.taskId
			, url           = getTaskRunnerUrl( taskId=taskId, siteContext=scheduleSettings.site_context )
			, port          = Val( scheduleSettings.http_port ?: "" ) ? scheduleSettings.http_port : 80
			, username      = scheduleSettings.http_username  ?: ""
			, password      = scheduleSettings.http_password  ?: ""
			, proxyServer   = scheduleSettings.proxy_server   ?: ""
			, proxyPort     = scheduleSettings.proxy_port     ?: ""
			, proxyUser     = scheduleSettings.proxy_user     ?: ""
			, proxyPassword = scheduleSettings.proxy_password ?: ""
			, startdate     = DateFormat( arguments.nextAttemptDate, "yyyy-mm-dd" )
			, startTime     = TimeFormat( arguments.nextAttemptDate, "HH:mm:ss" )
			, interval      = "Once"
			, hidden        = true
			, autoDelete    = true
		);

		$getPresideObject( "taskmanager_adhoc_task" ).updateData(
			  id   = arguments.taskId
			, data = {
				  status            = "requeued"
				, last_error        = SerializeJson( arguments.error )
				, attempt_count     = arguments.attemptCount
				, next_attempt_date = arguments.nextAttemptDate
				, finished_on       = _now()
			  }
		);

		return;
	}

	/**
	 * Sets progress on a task
	 *
	 * @autodoc  true
	 * @taskId   ID of the task
	 * @progress Progress percentage of the task
	 */
	public void function setProgress( required string taskId, required numeric progress ) {
		$getPresideObject( "taskmanager_adhoc_task" ).updateData(
			  id   = arguments.taskId
			, data = { progress_percentage=arguments.progress }
		);
	}

	/**
	 * Sets the result of a task
	 *
	 * @autodoc  true
	 * @taskId   ID of the task
	 * @result   The task result (will be serialized when saving against DB record)
	 */
	public void function setResult( required string taskId, required any result ) {
		$getPresideObject( "taskmanager_adhoc_task" ).updateData(
			  id   = arguments.taskId
			, data = { result=SerializeJson( arguments.result ) }
		);
	}

	/**
	 * Sets the result URL of a task. Useful/required when wanting
	 * to use built in admin UIs for progress / result viewing of tasks
	 *
	 * @autodoc   true
	 * @taskId    ID of the task
	 * @resultUrl The URL for viewing the result of the task
	 */
	public void function setResultUrl( required string taskId, required any resultUrl ) {
		$getPresideObject( "taskmanager_adhoc_task" ).updateData(
			  id   = arguments.taskId
			, data = { result_url=arguments.resultUrl }
		);
	}

	/**
	 * Returns progress of the given task as a struct. Struct keys:
	 * [id, progress, status, result].
	 *
	 * @autodoc true
	 * @taskId  ID of the task whose progress you wish to get
	 */
	public struct function getProgress( required string taskId ) {
		var task = getTask( arguments.taskId );

		for( var t in task ) {
			var timeTaken     = 0;
			var timeRemaining = 0;

			switch( t.status ) {
				case "running":
					timeTaken = DateDiff( 's', t.started_on, _now() );
					if ( Val( t.progress_percentage ) && t.progress_percentage < 100 ) {
						timeRemaining = Round( ( timeTaken / t.progress_percentage ) * ( 100-t.progress_percentage ) );
					}
				break;
				case "requeued":
				case "succeeded":
				case "failed":
					timeTaken = DateDiff( 's', t.started_on, t.finished_on );
				break;
			}
			return {
				  id            = t.id
				, status        = t.status
				, progress      = t.progress_percentage
				, log           = t.log
				, resultUrl     = t.result_url
				, returnUrl     = t.return_url
				, result        = IsJson( t.result ?: "" ) ? DeserializeJson( t.result ) : {}
				, timeTaken     = timeTaken
				, timeRemaining = timeRemaining
			};
		}

		return {};
	}


	/**
	 * Discards the given task
	 *
	 * @autodoc true
	 * @taskId  ID of the task to discard
	 */
	public boolean function discardTask( required string taskId ) {
		$getPresideObject( "taskmanager_adhoc_task" ).deleteData( id=arguments.taskId );

		return true;
	}

	/**
	 * Returns a struct with information about the next retry attempt for a task.
	 * Keys are: "nextAttemptDate", "totalAttempts". Returns an empty struct
	 * if task cannot be retried.
	 *
	 * @autodoc true
	 * @taskId  ID of the task
	 *
	 */
	public struct function getNextAttemptInfo( required string taskId ) {
		var task          = getTask( arguments.taskId );
		var retryConfig   = IsJson( task.retry_interval ?: "" ) ? DeserializeJson( task.retry_interval ) : [];
		var maxAttempts   = 0;
		var nextInterval  = 0;
		var totalAttempts = Val( task.attempt_count ) + 1;
		var info          = {
			  totalAttempts   = totalAttempts
			, nextAttemptDate = ""
		};

		for( var interval in retryConfig ) {
			maxAttempts += Val( interval.tries ?: "" );

			if ( maxAttempts > totalAttempts ) {
				info.nextAttemptDate = DateTimeFormat( DateAdd( "s", Val( interval.interval ?: "" ), _now() ), "yyyy-mm-dd HH:nn:ss" );
				break;
			}
		}

		return info;
	}

	public string function getTaskRunnerUrl( required string taskId, required string siteContext ) {
		var siteSvc    = _getSiteService();
		var site       = siteSvc.getSite( Len( Trim( arguments.siteContext ) ) ? arguments.siteContext : siteSvc.getActiveSiteId() );
		var serverName = ( site.domain ?: cgi.server_name );

		return "http://" & serverName & "/taskmanager/runadhoctask/?taskId=" & arguments.taskId;
	}

// PRIVATE HELPERS
	private any function _getTaskLogger( required string taskId ) {
		return new TaskManagerLoggerWrapper(
			  logboxLogger   = _getLogger()
			, taskRunId      = arguments.taskId
			, taskHistoryDao = $getPresideObject( "taskmanager_adhoc_task" )
		);
	}

	private any function _getTaskProgressReporter( required string taskId ) {
		return new AdHocTaskProgressReporter(
			  adhocTaskManagerService = this
			, taskId                  = arguments.taskId
		);
	}

	private boolean function _inChildThread() {
		var currentThreadName = CreateObject( "java", "java.lang.Thread" ).currentThread().getThreadGroup().getName();

		return currentThreadName.findNoCase( "cfthread" );
	}

	private date function _now() {
		return Now(); // to help with automated tests
	}

	private string function _serializeRetryInterval( required any retryInterval ) {
		var raw       = IsArray( arguments.retryInterval ) ? Duplicate( arguments.retryInterval ) : [ Duplicate( arguments.retryInterval ) ];
		var converted = [];

		for( var config in raw ) {
			converted.append({
				  tries    = Val( config.tries ?: 1 )
				, interval = _isTimespan( config.interval ?: "" ) ? _timespanToSeconds( config.interval ) : config.interval
			});
		}

		return SerializeJson( converted );
	}

	private any function _isTimespan( required any input ) {
		return SerializeJson( arguments.input ).reFindNoCase( "^createTimeSpan\(" ) > 0;
	}
	private any function _timespanToSeconds( required any input ) {
		var secondsInADay = 86400;

		return Round( Val( arguments.input ) * secondsInADay );
	}

// GETTERS AND SETTERS
	private any function _getTaskScheduler() {
		return _taskScheduler;
	}
	private void function _setTaskScheduler( required any taskScheduler ) {
		_taskScheduler = arguments.taskScheduler;
	}

	private any function _getSiteService() {
		return _siteService;
	}
	private void function _setSiteService( required any siteService ) {
		_siteService = arguments.siteService;
	}

	private any function _getLogger() {
		return _logger;
	}
	private void function _setLogger( required any logger ) {
		_logger = arguments.logger;
	}

	private numeric function _getMaxTimeout() {
		return _maxTimeout;
	}
	private void function _setMaxTimeout( required numeric maxTimeout ) {
		_maxTimeout = arguments.maxTimeout;
	}

}