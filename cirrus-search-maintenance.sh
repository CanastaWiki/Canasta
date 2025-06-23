get_mediawiki_cirrus_search_server() {
    server=$(get_mediawiki_variable wgCirrusSearchServers first)
    if [ -z "$server" ]; then
        server=$(php /getMediawikiSettings.php --variable=wgCirrusSearchClusters --format=string)
    fi
    get_hostname_with_port "$server" 9200
}

WG_CIRRUS_SEARCH_SERVER=$(get_mediawiki_cirrus_search_server)

# Pause setup until ElasticSearch starts running
waitelastic() {
    if [ -n "$es_started" ]; then
        return 0; # already started
    fi
    echo >&2 'Waiting for elasticsearch to start'
    /wait-for-it.sh -t 60 "$WG_CIRRUS_SEARCH_SERVER"
    for i in {300..0}; do
        result=0
        output=$(wget --timeout=1 -q -O - "http://$WG_CIRRUS_SEARCH_SERVER/_cat/health") || result=$?
        if [[ "$result" = 0 && $(echo "$output"|awk '{ print $4 }') = "green" ]]; then
            break
        fi
        if [ "$result" = 0 ]; then
            echo >&2 "Waiting for elasticsearch health status changed from [$(echo "$output"|awk '{ print $4 }')] to [green]..."
        else
            echo >&2 'Waiting for elasticsearch to start...'
        fi
        sleep 1
    done
    if [ "$i" = 0 ]; then
        echo >&2 'Elasticsearch is not ready for use'
        echo "$output"
        return 1
    fi
    echo >&2 'Elasticsearch started successfully'
    es_started="1"
    return 0
}

WG_SEARCH_TYPE=$(get_mediawiki_variable wgSearchType)

if [ "$WG_SEARCH_TYPE" == 'CirrusSearch' ]; then
    run_maintenance_script_if_needed 'maintenance_CirrusSearch_updateConfig' "${EXTRA_MW_MAINTENANCE_CIRRUSSEARCH_UPDATECONFIG}${MW_MAINTENANCE_CIRRUSSEARCH_UPDATECONFIG}${MW_VERSION}" \
        'extensions/CirrusSearch/maintenance/UpdateSearchIndexConfig.php --reindexAndRemoveOk --indexIdentifier now' && \
    run_maintenance_script_if_needed 'maintenance_CirrusSearch_forceIndex' "${EXTRA_MW_MAINTENANCE_CIRRUSSEARCH_FORCEINDEX}${MW_MAINTENANCE_CIRRUSSEARCH_FORCEINDEX}${MW_VERSION}" \
        'extensions/CirrusSearch/maintenance/ForceSearchIndex.php --skipLinks --indexOnSkip' \
        'extensions/CirrusSearch/maintenance/ForceSearchIndex.php --skipParse'
fi
