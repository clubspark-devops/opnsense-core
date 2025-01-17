{#
 # Copyright (c) 2022 Deciso B.V.
 # All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without modification,
 # are permitted provided that the following conditions are met:
 #
 # 1. Redistributions of source code must retain the above copyright notice,
 #    this list of conditions and the following disclaimer.
 #
 # 2. Redistributions in binary form must reproduce the above copyright notice,
 #    this list of conditions and the following disclaimer in the documentation
 #    and/or other materials provided with the distribution.
 #
 # THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 # INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 # AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 # AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 # OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 # SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 # INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 # CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 # ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 # POSSIBILITY OF SUCH DAMAGE.
 #}

{% set theme_name = ui_theme|default('opnsense') %}
<script src="{{ cache_safe('/ui/js/chart.min.js') }}"></script>
<script src="{{ cache_safe('/ui/js/chartjs-plugin-streaming.min.js') }}"></script>
<script src="{{ cache_safe('/ui/js/chartjs-plugin-colorschemes.js') }}"></script>
<script src="{{ cache_safe('/ui/js/moment-with-locales.min.js') }}"></script>
<script src="{{ cache_safe('/ui/js/chartjs-adapter-moment.js') }}"></script>
<link rel="stylesheet" type="text/css" href="{{ cache_safe(theme_file_or_default('/css/chart.css', theme_name)) }}" rel="stylesheet" />
<link rel="stylesheet" type="text/css" href="{{ cache_safe(theme_file_or_default('/css/dns-overview.css', theme_name)) }}" rel="stylesheet"/>

<script>
    $(document).ready(function() {
        $('#info').hide();

        function set_alpha(color, opacity) {
            const op = Math.round(Math.min(Math.max(opacity || 1, 0), 1) * 255);
            return color + op.toString(16).toUpperCase();
        }

        function create_chart(target, stepsize, feed_data, logarithmic) {
            const ctx = target[0].getContext('2d');
            const config = {
                type: 'line',
                data: {
                    datasets: [{
                        label: 'Total queries',
                        data: feed_data,
                        borderWidth: 1,
                        parsing: {
                            yAxisKey: 'y.total'
                        }
                    }, {
                        label: 'Blocked',
                        data: feed_data,
                        borderWidth: 1,
                        parsing: {
                            yAxisKey: 'y.blocked'
                        }
                    }]
                },
                options: {
                    maintainAspectRatio: false,
                    responsive: true,
                    aspectRatio: 1,
                    elements: {
                        line: {
                            fill: false,
                            cubicInterpolationMode: 'monotone',
                            clip: 0,
                        },
                        point: {
                            radius: 0
                        }
                    },
                    layout: {
                        padding: {
                            left: 40,
                            right: 50,
                            bottom: 20
                        }
                    },
                    scales: {
                        x: {
                            type: 'time',
                            time: {
                                tooltipFormat:'HH:mm',
                                unit:'minute',
                                stepSize: stepsize,
                                minUnit: 'minute',
                                displayFormats: {
                                    minute: 'HH:mm'
                                }
                            }
                        },
                        y: {
                            ticks: {
                                callback: function (value, index, values) {
                                    /* workaround for chart.js v3: no proper handling for
                                     * logarithmic scale when 0 values are supplied.
                                     */
                                    if (index === 0) {
                                        return '0';
                                    }
                                    /* Don't show decimal values on the y-axis */
                                    if (Math.floor(value) == value) {
                                        return value;
                                    }
                                },
                                autoSkip: true,
                                autoSkipPadding: 10
                            },
                            type: logarithmic ? 'logarithmic' : 'linear',
                            min: logarithmic ? 0.1 : 0,
                        }
                    },
                    plugins: {
                        tooltip: {
                            mode: 'nearest',
                            intersect: false,
                            callbacks: {
                                label: function(context) {
                                    let val = context.parsed.y == 0.1 ? 0 : context.parsed.y
                                    return context.dataset.label + ': ' + val.toLocaleString();
                                }
                            }
                        },
                        legend: {
                            display: true
                        },
                        colorschemes: {
                            scheme: 'brewer.DarkTwo8'
                        }
                    }
                }
            };

            return new Chart(ctx, config);
        }

        function create_client_chart(target, stepsize, feed_data, logarithmic) {
            const ctx = target[0].getContext('2d');
            const config = {
                type: 'bubble',
                data: {
                    datasets: feed_data
                },
                options: {
                    maintainAspectRatio: false,
                    responsive: true,
                    aspectRatio: 1,
                    layout: {
                        padding: {
                            left: 40,
                            right: 50,
                            bottom: 20
                        }
                    },
                    scales: {
                        x: {
                            type: 'time',
                            time: {
                                tooltipFormat:'HH:mm',
                                unit:'minute',
                                stepSize: stepsize,
                                minUnit: 'minute',
                                displayFormats: {
                                    minute: 'HH:mm'
                                }
                            }
                        },
                        y: {
                            ticks: {
                                callback: function (value, index, values) {
                                    if (index === 0) {
                                        return '0';
                                    }
                                    /* Don't show decimal values on the y-axis */
                                    if (Math.floor(value) == value) {
                                        return value;
                                    }
                                },
                                autoSkip: true,
                                autoSkipPadding: 10
                            },
                            type: logarithmic ? 'logarithmic' : 'linear',
                            min: logarithmic ? 0.1 : 0,
                        }
                    },
                    plugins: {
                        tooltip: {
                            mode: 'nearest',
                            intersect: false,
                            filter: function(context) {
                                return context.parsed.y != 0.1;
                            },
                            callbacks: {
                                label: function(context) {
                                    /* Logarithmic scaling workaround continuation: replace the earlier
                                     * supplied 0.1 values (if any) with 0 in the tooltip menu
                                     */
                                    if (context) {
                                        if (context.parsed.y == 0.1) {
                                            return null;
                                        }
                                        let label = context.dataset.label
                                        let val = context.parsed.y == 0.1 ? 0 : context.parsed.y
                                        return label + ' (' + val.toLocaleString() + ')';
                                    }
                                },
                                title: function(context) {
                                    if (context[0]) {
                                        /* Default bubble chart has no tooltip title, add the formatted time */
                                        return context[0].formattedValue.split(',')[0].replace(/[{()}]/g, '');;
                                    }
                                }
                            }
                        },
                        legend: {
                            display: false
                        },
                        colorschemes: {
                            scheme: 'brewer.DarkTwo8'
                        }
                    }
                }
            };

            return new Chart(ctx, config);
        }

        function formatQueryData(data, logarithmic) {
            let formatted = [];
            Object.keys(data).forEach((key, index) => {
                /* workaround for logarithmic scale, see https://github.com/chartjs/Chart.js/issues/9629 */
                if (logarithmic) {
                    Object.keys(data[key]).forEach((k, i) => {
                        if (data[key][k] == 0) {
                            data[key][k] = 0.1
                        }
                    })
                }
                formatted.push({
                    x: key * 1000,
                    y: data[key]
                });
            });

            /* Add a redundant data step to end the chart time axis properly */
            if (formatted.length > 0) {
                let lastVal = formatted[formatted.length - 1];
                let interval = $("#timeperiod").val() == 1 ? 60 : 600;
                let y_val = logarithmic ? 0.1 : 0
                formatted.push({
                    x: lastVal.x + (interval * 1000),
                    y: {
                        "total": y_val,
                        "blocked": y_val
                    }
                });
            }

            return formatted;
        }

        function formatClientData(data, logarithmic) {
            let uniqueClients = [...new Set(
                Object.values(data)
                    .map(Object.keys)
                    .reduce((a, b) => a.concat(b), [])
            )]
            let formatted = [];
            // split into different datasets
            for (let i = 0; i < uniqueClients.length; i++) {
                let tmp = []
                let backup_val = logarithmic ? 0.1 : null;
                Object.keys(data).forEach((key, index) => {
                    /* Similarly with the query line chart, the bubble chart cannot handle null values on a log scale */
                    tmp.push({
                        x: key * 1000,
                        y: data[key].hasOwnProperty(uniqueClients[i]) ? data[key][uniqueClients[i]] : backup_val,
                        r: data[key].hasOwnProperty(uniqueClients[i]) ? 4 : 0
                    })
                });

                /* Add a redundant data step to end the chart time axis properly */
                if (tmp.length > 0) {
                    let lastVal = tmp[tmp.length - 1];
                    let interval = $("#timeperiod-clients").val() == 1 ? 60 : 600;
                    tmp.push({
                        x: lastVal.x + (interval * 1000),
                        y: backup_val,
                        r: 0
                    });
                }

                let colors = Chart.colorschemes.brewer.DarkTwo8.length;
                let colorIdx = i - parseInt(i / colors) * colors;
                let bgColor = Chart.colorschemes.brewer.DarkTwo8[colorIdx];
                formatted.push({
                    label: uniqueClients[i],
                    data: tmp,
                    borderWidth: 1,
                    backgroundColor: set_alpha(bgColor, 0.5),
                    borderColor: bgColor,
                    hoverRadius: 10
                })
            }
            return formatted;
        }

        function updateQueryChart(use_log=false) {
            let def = new $.Deferred();
            ajaxGet('/api/unbound/overview/rolling/' + $("#timeperiod").val(), {}, function(data, status) {
                let formatted = formatQueryData(data, use_log);
                g_queryChart.config.options.scales.x.time.stepSize = $("#timeperiod").val() == 1 ? 5 : 60;
                g_queryChart.config.data.datasets.forEach(function(dataset) {
                    dataset.data = formatted;
                });
                if (use_log) {
                    g_queryChart.config.options.scales.y.type = 'logarithmic';
                    g_queryChart.config.options.scales.y.min = 0.1;
                } else {
                    g_queryChart.config.options.scales.y.type = 'linear';
                    g_queryChart.config.options.scales.y.min = 0;
                }
                g_queryChart.update();
                def.resolve();
            });
            return def;
        }

        function updateClientChart(use_log=false) {
            let def = new $.Deferred();
            ajaxGet('/api/unbound/overview/rolling/' + $("#timeperiod-clients").val() + '/1', {}, function(data, status) {
                let formatted = formatClientData(data, use_log);
                g_clientChart.config.options.scales.x.time.stepSize = $("#timeperiod-clients").val() == 1 ? 5 : 60;
                g_clientChart.config.data.datasets = formatted;
                if (use_log) {
                    g_clientChart.config.options.scales.y.type = 'logarithmic';
                    g_clientChart.config.options.scales.y.min = 0.1;
                } else {
                    g_clientChart.config.options.scales.y.type = 'linear';
                    g_clientChart.config.options.scales.y.min = 0;
                }
                g_clientChart.update();
                def.resolve();
            });
            return def;
        }

        function createTopList(id, data, type) {
            ajaxGet('/api/unbound/overview/isBlockListEnabled', {}, function(bl_enabled, status) {
                let class_type = type == "pass" ? "block-domain" : "whitelist-domain";
                let icon_type = type == "pass" ? "fa fa-ban text-danger" : "fa fa-pencil text-info";
                for (let i = 0; i < 10; i++) {
                    let domain = Object.keys(data)[i];
                    let statObj = Object.values(data)[i];
                    if (typeof domain == 'undefined' || typeof statObj == 'undefined') {
                        $('#' + id).append(
                            '<li class="list-group-item list-group-item-border top-item">' +
                            (i + 1) + '. ' +
                            '<span class="counter">0 (0.0%)' +
                            '</span></li>'
                        )
                        continue;
                    }

                    let icon = '<button class="'+ class_type + '" data-value="'+ domain +'" ' +
                    'data-toggle="tooltip" style="margin-left: 10px;"><i class="' + icon_type + '"></i></button>'

                    if (bl_enabled.enabled == 0) {
                        icon = '';
                    }

                    let bl = statObj.hasOwnProperty('blocklist') ? '(' + statObj.blocklist + ')' : '';
                    $('#' + id).append(
                        '<li class="list-group-item list-group-item-border top-item">' +
                        (i + 1) + '. ' + domain + ' ' + bl +
                        '<span class="counter">'+ statObj.total +' (' + statObj.pcnt +'%)' +
                        icon +
                        '</span></li>'
                    )
                }
                $(".block-domain").tooltip().attr('title', "{{ lang._('Block Domain') }}");
                $(".whitelist-domain").tooltip().attr('title', "{{ lang._('Whitelist Domain') }}");
            });
        }

        function create_or_update_totals() {
            ajaxGet('/api/unbound/overview/totals/10', {}, function(data, status) {
                $('.top-item').remove();

                $('#totalCounter').html(data.total);
                $('#blockedCounter').html(data.blocked.total + " (" + data.blocked.pcnt + "%)");
                $('#sizeCounter').html(data.blocklist_size);
                $('#resolvedCounter').html(data.resolved.total + " (" + data.resolved.pcnt + "%)");

                createTopList('top', data.top, 'pass');
                createTopList('top-blocked', data.top_blocked, 'block');

                $('#top li:nth-child(even)').addClass('odd-bg');
                $('#top-blocked li:nth-child(even)').addClass('odd-bg');

                $('#bannersub').html("Starting from " + (new Date(data.start_time * 1000)).toLocaleString());
            });
        }

        g_queryChart = null;
        g_clientChart = null;

        /* Initial page load */
        function do_startup() {
            let def = new $.Deferred();
            ajaxGet('/api/unbound/overview/isEnabled', {}, function(is_enabled, status) {
                if (is_enabled.enabled == 0) {
                    def.reject();
                    return;
                }

                def.resolve();

                if (window.localStorage && window.localStorage.getItem("api.unbound.overview.timeperiod") !== null) {
                    $("#timeperiod").val(window.localStorage.getItem("api.unbound.overview.timeperiod"));
                }
                $('#timeperiod').selectpicker('refresh');

                if (window.localStorage && window.localStorage.getItem("api.unbound.overview.timeperiodclients") !== null) {
                    $("#timeperiod-clients").val(window.localStorage.getItem("api.unbound.overview.timeperiodclients"));
                }
                $('#timeperiod-clients').selectpicker('refresh');

                g_queryChart = create_chart($("#rollingChart"), 60, [], false);
                g_clientChart = create_client_chart($("#rollingChartClient"), 60, [], false);
                updateQueryChart($("#toggle-log-qchart")[0].checked);
                updateClientChart($("#toggle-log-cchart")[0].checked);
                create_or_update_totals();
            });

            return def;
        }

        $("#timeperiod").change(function() {
            if (window.localStorage) {
                window.localStorage.setItem("api.unbound.overview.timeperiod", $(this).val());
            }
            updateQueryChart($("#toggle-log-qchart")[0].checked);
        });

        $("#timeperiod-clients").change(function() {
            if (window.localStorage) {
                window.localStorage.setItem("api.unbound.overview.timeperiodclients", $(this).val());
            }
            updateClientChart($("#toggle-log-cchart")[0].checked);
        });

        $("#toggle-log-qchart").change(function() {
            updateQueryChart(this.checked);
        })

        $("#toggle-log-cchart").change(function() {
            updateClientChart(this.checked);
        })

        $(document).on('click', '.block-domain', function() {
            $(this).remove("i").html('<i class="fa fa-spinner fa-spin"></i>');
            ajaxCall('/api/unbound/settings/updateBlocklist', {
                'domain': $(this).data('value'),
                'type': 'blocklists'
            }, function(data, status) {
                $(".block-domain").remove("i").html('<i class="fa fa-ban text-danger"></i>');
            });
        });

        $(document).on('click', '.whitelist-domain', function() {
            $(this).remove("i").html('<i class="fa fa-spinner fa-spin"></i>');
            ajaxCall('/api/unbound/settings/updateBlocklist', {
                'domain': $(this).data('value'),
                'type': 'whitelists'
            }, function(data, status) {
                $(".whitelist-domain").remove("i").html('<i class="fa fa-pencil text-info"></i>');
            });
        });

        do_startup().done(function() {
            $('.wrapper').show();
        }).fail(function() {
            $('.wrapper').hide();
            $('#info').show();
        });

        $('a[data-toggle="tab"]').on('shown.bs.tab', function (e) {
            if (e.target.id == 'query_details_tab') {
                $("#grid-queries").bootgrid('destroy');
                ajaxGet('/api/unbound/overview/isBlockListEnabled', {}, function(bl_enabled, status) {
                    let grid_queries = $("#grid-queries").UIBootgrid({
                        search:'/api/unbound/overview/searchQueries/',
                        options: {
                            rowSelect: false,
                            multiSelect: false,
                            selection: false,
                            formatters: {
                                "timeformatter": function (column, row) {
                                    return moment.unix(row.time).local().format('YYYY-MM-DD HH:mm:ss');
                                },
                                "resolveformatter": function (column, row) {
                                    return row.resolve_time_ms + 'ms';
                                },
                                "commands": function (column, row) {
                                    let btn = '';
                                    if (bl_enabled.enabled == 0) {
                                        return btn;
                                    } else if (row.action == 'Pass') {
                                        btn = '<button type="button" class="btn-secondary block-domain" data-domain=' + row.domain + ' data-toggle="tooltip"><i class="fa fa-ban text-danger"></i></button> ';
                                    } else if (row.action == 'Block') {
                                        btn = '<button type="button" class="btn-secondary whitelist-domain" data-domain=' + row.domain + ' data-toggle="tooltip"><i class="fa fa-pencil text-info"></i></button>';
                                    }
                                    return btn;
                                },
                            },
                            statusMapping: {
                                0: "query-success",
                                1: "info",
                                2: "query-warning",
                                3: "query-danger",
                                4: "danger"
                            }
                        }
                    }).on("loaded.rs.jquery.bootgrid", function (e) {
                        if (bl_enabled.enabled == 0) {
                            $(".hide-col").css("display", "none");
                        } else {
                            $(".hide-col").css('display', '');
                        }
                        $(".block-domain").tooltip().attr('title', "{{ lang._('Block Domain') }}");
                        $(".whitelist-domain").tooltip().attr('title', "{{ lang._('Whitelist Domain') }}");
                        grid_queries.find(".block-domain").on("click", function(e) {
                            $(this).remove("i").html('<i class="fa fa-spinner fa-spin"></i>');
                            ajaxCall('/api/unbound/settings/updateBlocklist', {
                                'domain': $(this).data('domain'),
                                'type': 'blocklists',
                            }, function(data, status) {
                                    let btn = grid_queries.find(".block-domain");
                                    btn.remove("i").html('<i class="fa fa-ban text-danger"></i>');
                            });
                        });

                        grid_queries.find(".whitelist-domain").on("click", function(e) {
                            $(this).remove("i").html('<i class="fa fa-spinner fa-spin"></i>');
                            ajaxCall('/api/unbound/settings/updateBlocklist', {
                                'domain': $(this).data('domain'),
                                'type': 'whitelists',
                            }, function(data, status) {
                                    let btn = grid_queries.find(".whitelist-domain");
                                    btn.remove("i").html('<i class="fa fa-pencil text-info"></i>');
                            });
                        });
                    });
                })

            }
            if (e.target.id == 'query_overview_tab') {
                create_or_update_totals();
                updateQueryChart($("#toggle-log-qchart")[0].checked);
                updateClientChart($("#toggle-log-cchart")[0].checked);
            }
        });
    });

</script>

<div id="info" class="alert alert-warning" role="alert">
    {{ lang._('Local gathering of statistics is not enabled. Enable it in Reporting Settings page.') }}
    <br />
    <a href="/reporting_settings.php">{{ lang._('Go to the Reporting configuration') }}</a>
</div>
<div class="wrapper">
    <ul class="nav nav-tabs" data-tabs="tabs" id="maintabs" style="border-bottom: none">
        <li class="active"><a data-toggle="tab" href="#query-overview" id="query_overview_tab">{{ lang._('Overview') }}</a></li>
        <li><a data-toggle="tab" href="#query-details" id="query_details_tab">{{ lang._('Details') }}</a></li>
    </ul>
    <div class="tab-content content-box" style="padding: 10px; border-top: 1px solid #E5E5E5;">
        <div id="query-overview" class="tab-pane fade in active">
            <div class="content-box" style="margin-bottom: 10px;">
                <div id="counters" class="container-fluid">
                    <div class="col-md-12">
                        <h3 id="bannersub"></h3>
                    </div>
                    <div class="row" style="margin-bottom: 20px; margin-top: 20px;">
                        <div class="banner col-xs-3 justify-content-center">
                            <div class="stats-element">
                                <div class="stats-icon">
                                    <i class="large-icon fa fa-cogs text-success" aria-hidden="true"></i>
                                </div>
                                <div class="stats-text">
                                    <h2 id="totalCounter" class="stats-counter-text"></h2>
                                    <p class="stats-inner-text">{{ lang._('Total')}}</p>
                                </div>
                            </div>
                        </div>
                        <div class="banner col-xs-3 justify-content-center">
                            <div class="stats-element">
                                <div class="stats-icon">
                                    <i class="large-icon fa fa-arrows-v text-info" aria-hidden="true"></i>
                                </div>
                                <div class="stats-text">
                                    <h2 id="resolvedCounter" class="stats-counter-text"></h2>
                                    <p class="stats-inner-text">{{ lang._('Resolved') }}</p>
                                </div>
                            </div>
                        </div>
                        <div class="banner col-xs-3 justify-content-center">
                            <div class="stats-element">
                                <div class="stats-icon">
                                    <i class="large-icon fa fa-hand-paper-o text-danger" aria-hidden="true"></i>
                                </div>
                                <div class="stats-text">
                                    <h2 id="blockedCounter" class="stats-counter-text"></h2>
                                    <p class="stats-inner-text pull-right">{{ lang._('Blocked') }}</p>
                                </div>
                            </div>
                        </div>
                        <div class="banner col-xs-3 justify-content-center">
                            <div class="stats-element">
                                <div class="stats-icon">
                                    <i class="large-icon fa fa-list text-primary" aria-hidden="true"></i>
                                </div>
                                <div class="stats-text">
                                    <h2 id="sizeCounter" class="stats-counter-text"></h2>
                                    <p class="stats-inner-text">{{ lang._('Size of blocklist') }}</p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            <div class="content-box" style="margin-bottom: 10px;">
                <div id="graph" class="container-fluid">
                    <div class="row justify-content-center" style="display: flex; flex-wrap: wrap;">
                        <div class="col-md-4"></div>
                        <div class="col-md-4 text-center" style="padding: 10px;">
                            <span id="qGraphTitle" style="padding: 5px;"><b>{{ lang._('Queries over the last ') }}</b></span>
                            <select class="selectpicker" id="timeperiod" data-width="auto">
                                <option value="24">{{ lang._('24 Hours') }}</option>
                                <option value="12">{{ lang._('12 Hours') }}</option>
                                <option value="1">{{ lang._('1 Hour') }}</option>
                            </select>
                        </div>
                        <div class="col-md-2"></div>
                        <div class="col-md-2">
                            <div class="vertical-center">
                                <label class="h-100" style="margin-right: 5px;">{{ lang._('Logarithmic') }}</label>
                                <input id="toggle-log-qchart" type="checkbox"></input>
                            </div>
                        </div>
                    </div>
                    <div class="row">
                        <div class="col-2"></div>
                        <div class="col-8">
                            <div class="chart-container">
                                <canvas id="rollingChart"></canvas>
                            </div>
                        </div>
                        <div class="col-2"></div>
                    </div>
                </div>
            </div>
            <div class="content-box" style="margin-bottom: 10px;">
                <div id="graph" class="container-fluid">
                    <div class="row justify-content-center" style="display: flex; flex-wrap: wrap;">
                        <div class="col-md-4"></div>
                        <div class="col-md-4 text-center" style="padding: 10px;">
                            <span id="cGraphTitle" style="padding: 5px;"><b>{{ lang._('Top 10 client activity over the last ') }}</b></span>
                            <select class="selectpicker" id="timeperiod-clients" data-width="auto">
                                <option value="24">{{ lang._('24 Hours') }}</option>
                                <option value="12">{{ lang._('12 Hours') }}</option>
                                <option value="1">{{ lang._('1 Hour') }}</option>
                            </select>
                        </div>
                        <div class="col-md-2"></div>
                        <div class="col-md-2">
                            <div class="vertical-center">
                                <label class="h-100" style="margin-right: 5px;">Logarithmic</label>
                                <input id="toggle-log-cchart" type="checkbox"></input>
                            </div>
                        </div>
                    </div>
                    <div class="row">
                        <div class="col-2"></div>
                        <div class="col-8">
                            <div class="chart-container">
                                <canvas id="rollingChartClient"></canvas>
                            </div>
                        </div>
                        <div class="col-2"></div>
                    </div>
                </div>
            </div>
            <div class="content-box">
                <div class="container-fluid">
                    <div class="row">
                        <div class="col-md-6">
                            <div class="top-list">
                                <ul class="list-group" id="top">
                                    <li class="list-group-item list-group-item-border">
                                        <b>{{ lang._('Top passed domains') }}</b>
                                    </li>
                                </ul>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="top-list">
                                <ul class="list-group" id="top-blocked">
                                    <li class="list-group-item list-group-item-border">
                                        <b>{{ lang._('Top blocked domains') }}</b>
                                    </li>
                                </ul>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div id="query-details" class="tab-pane fade in">
            <table id="grid-queries" class="table table-condensed">
                <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">{{ lang._('ID') }}</th>
                    <th data-column-id="status" data-type="numeric" data-visible="false" data-formatter="statusformatter">{{ lang._('status') }}</th>
                    <th data-column-id="time" data-type="string" data-formatter="timeformatter">{{ lang._('Time') }}</th>
                    <th data-column-id="client" data-type="string">{{ lang._('Client') }}</th>
                    <th data-column-id="family" data-width="6em" data-visible="false" data-type="string">{{ lang._('Family') }}</th>
                    <th data-column-id="type" data-width="6em" data-type="string">{{ lang._('Type') }}</th>
                    <th data-column-id="domain" data-type="string">{{ lang._('Domain') }}</th>
                    <th data-column-id="action" data-width="6em" data-type="string">{{ lang._('Action') }}</th>
                    <th data-column-id="source" data-type="string">{{ lang._('Source') }}</th>
                    <th data-column-id="rcode" data-type="string">{{ lang._('Return Code') }}</th>
                    <th data-column-id="resolve_time_ms" data-type="string" data-formatter="resolveformatter">{{ lang._('Resolve time') }}</th>
                    <th data-column-id="ttl" data-type="string">{{ lang._('TTL') }}</th>
                    <th data-column-id="blocklist" data-type="string">{{ lang._('Blocklist') }}</th>
                    <th data-header-css-class="hide-col" data-css-class="hide-col" data-column-id="commands" data-width="7em" data-formatter="commands" data-sortable="false">{{ lang._('Command') }}</th>
                </tr>
                </thead>
                <tbody>
                </tbody>
                <tfoot>
                </tfoot>
            </table>
        </div>
    </div>
</div>
