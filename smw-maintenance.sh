# Run incomplete Semantic MediaWiki setup tasks
SMW_INCOMPLETE_TASKS=$(php /getSMWSettings.php --IncompleteSetupTasks)
for task in $SMW_INCOMPLETE_TASKS
do
     case $task in
        smw-updateentitycollation-incomplete)
            run_maintenance_script_if_needed 'maintenance_semantic_updateEntityCollation' "always" \
                'extensions/SemanticMediaWiki/maintenance/updateEntityCollation.php'
            ;;
        smw-updateentitycountmap-incomplete)
            run_maintenance_script_if_needed 'maintenance_semantic_updateEntityCountMap' "always" \
                'extensions/SemanticMediaWiki/maintenance/updateEntityCountMap.php'
            ;;
        *)
            echo >&2 "######## Unknown SMW maintenance setup task - $task ########"
            ;;
     sac
done
