# mysqlbinlog 디코딩 샘플 — binlog_row_image = FULL
# (binlog_tracking.md §3.4 참조용 / sanitize 됨: server-id·GTID UUID·DB명은 placeholder)
# 같은 INSERT→UPDATE→DELETE 시퀀스를 FULL / MINIMAL 로 디코딩해 BI/AI 차이를 비교하기 위한 자료.
# 데모 테이블 rowimg_demo(@1=PK INT, @2/@3=VARSTRING, @4=INT) 에 대한 1개 트랜잭션.
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=1*/;
/*!50003 SET @OLD_COMPLETION_TYPE=@@COMPLETION_TYPE,COMPLETION_TYPE=0*/;
DELIMITER /*!*/;
#260605 15:11:14 server id <server-id>  end_log_pos 4719794 	GTID	last_committed=11935	sequence_number=11936	rbr_only=yes
/*!50718 SET TRANSACTION ISOLATION LEVEL READ COMMITTED*//*!*/;
SET @@SESSION.GTID_NEXT= '<source-uuid>:19651'/*!*/;
#260605 15:11:14 server id <server-id>  end_log_pos 4719874 	Query	thread_id=35	exec_time=0	error_code=0
SET TIMESTAMP=1780672274/*!*/;
BEGIN
/*!*/;
#260605 15:11:14 server id <server-id>  end_log_pos 4719948 	Table_map: `<db>`.`rowimg_demo` mapped to number 125
# has_generated_invisible_primary_key=0
#260605 15:11:14 server id <server-id>  end_log_pos 4720010 	Write_rows: table id 125 flags: STMT_END_F
### INSERT INTO `<db>`.`rowimg_demo`
### SET
###   @1=1 /* INT meta=0 nullable=0 is_null=0 */
###   @2='a_init_1' /* VARSTRING(200) meta=200 nullable=1 is_null=0 */
###   @3='b_init_1' /* VARSTRING(200) meta=200 nullable=1 is_null=0 */
###   @4=10 /* INT meta=0 nullable=1 is_null=0 */
#260605 15:11:14 server id <server-id>  end_log_pos 4720084 	Table_map: `<db>`.`rowimg_demo` mapped to number 125
# has_generated_invisible_primary_key=0
#260605 15:11:14 server id <server-id>  end_log_pos 4720177 	Update_rows: table id 125 flags: STMT_END_F
### UPDATE `<db>`.`rowimg_demo`
### WHERE
###   @1=1 /* INT meta=0 nullable=0 is_null=0 */
###   @2='a_init_1' /* VARSTRING(200) meta=200 nullable=1 is_null=0 */
###   @3='b_init_1' /* VARSTRING(200) meta=200 nullable=1 is_null=0 */
###   @4=10 /* INT meta=0 nullable=1 is_null=0 */
### SET
###   @1=1 /* INT meta=0 nullable=0 is_null=0 */
###   @2='a_UPDATED_1' /* VARSTRING(200) meta=200 nullable=1 is_null=0 */
###   @3='b_init_1' /* VARSTRING(200) meta=200 nullable=1 is_null=0 */
###   @4=10 /* INT meta=0 nullable=1 is_null=0 */
#260605 15:11:14 server id <server-id>  end_log_pos 4720251 	Table_map: `<db>`.`rowimg_demo` mapped to number 125
# has_generated_invisible_primary_key=0
#260605 15:11:14 server id <server-id>  end_log_pos 4720316 	Delete_rows: table id 125 flags: STMT_END_F
### DELETE FROM `<db>`.`rowimg_demo`
### WHERE
###   @1=1 /* INT meta=0 nullable=0 is_null=0 */
###   @2='a_UPDATED_1' /* VARSTRING(200) meta=200 nullable=1 is_null=0 */
###   @3='b_init_1' /* VARSTRING(200) meta=200 nullable=1 is_null=0 */
###   @4=10 /* INT meta=0 nullable=1 is_null=0 */
#260605 15:11:14 server id <server-id>  end_log_pos 4720347 	Xid = 437914
COMMIT/*!*/;
SET @@SESSION.GTID_NEXT= 'AUTOMATIC' /* added by mysqlbinlog */ /*!*/;
DELIMITER ;
# End of log file
/*!50003 SET COMPLETION_TYPE=@OLD_COMPLETION_TYPE*/;
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=0*/;
