locals {
  all_instances = { for name, instance in aws_instance.node : name => {
    id     = instance.id
    region = local.node_region[name]
  } }

  # Non-primary regions get their own Server Info log widget (Logs Insights
  # widgets are the only single-region widget type; metric widgets take a
  # per-metric region override instead)
  extra_dashboard_regions = [for r in sort(keys(local.regions)) : r if r != var.region]

  # Extra Server Info widgets sit directly under the primary one; everything
  # below shifts down accordingly (0 for single-region stacks)
  dashboard_y_offset = 6 * length(local.extra_dashboard_regions)
}

resource "aws_cloudwatch_dashboard" "rippled" {
  dashboard_name = "rippled-${var.environment}"

  dashboard_body = jsonencode({
    widgets = concat(
      # Alarm Status
      [
        {
          type   = "alarm"
          x      = 0
          y      = 0
          width  = 24
          height = 4
          properties = {
            title  = "Alarm Status"
            alarms = concat(
              [for name, _ in aws_instance.node : aws_cloudwatch_metric_alarm.server_state[name].arn],
              [for name, _ in aws_instance.node : aws_cloudwatch_metric_alarm.ledger_age[name].arn],
              [for name, _ in aws_instance.node : aws_cloudwatch_metric_alarm.peer_count[name].arn],
              [for name, _ in aws_instance.node : aws_cloudwatch_metric_alarm.cluster_count[name].arn],
              [for name, _ in aws_instance.node : aws_cloudwatch_metric_alarm.needs_reboot[name].arn],
              [aws_cloudwatch_metric_alarm.validator_miss_hourly.arn],
              [aws_cloudwatch_metric_alarm.validator_miss_daily.arn]
            )
          }
        }
      ],
      # Server Info from Logs
      [
        {
          type   = "log"
          x      = 0
          y      = 4
          width  = 24
          height = 6
          properties = {
            title  = "Server Info (Latest) - ${var.region}"
            region = var.region
            query  = "SOURCE '/rippled/${var.environment}/server-info' | fields @timestamp, instance_id, public_ip, build_version, server_state, pubkey_node, pubkey_validator, complete_ledgers, ledger_hash | sort @timestamp desc | dedup instance_id"
          }
        }
      ],
      # Server Info from Logs for non-primary regions, stacked below the primary
      # (log widgets are single-region)
      [
        for i, r in local.extra_dashboard_regions : {
          type   = "log"
          x      = 0
          y      = 10 + 6 * i
          width  = 24
          height = 6
          properties = {
            title  = "Server Info (Latest) - ${r}"
            region = r
            query  = "SOURCE '/rippled/${var.environment}/server-info' | fields @timestamp, instance_id, public_ip, build_version, server_state, pubkey_node, pubkey_validator, complete_ledgers, ledger_hash | sort @timestamp desc | dedup instance_id"
          }
        }
      ],
      # Server State and Uptime
      [
        {
          type   = "metric"
          x      = 0
          y      = 9 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Server State (5=proposing, 4=full)"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "rippled", "rippled_server_state", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 9 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Uptime (hours)"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "rippled", "rippled_uptime", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        }
      ],
      # Peers and Cluster
      [
        {
          type   = "metric"
          x      = 0
          y      = 15 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Peer Count"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "rippled", "rippled_peers", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 15 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Cluster Count"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "rippled", "rippled_cluster_count", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        }
      ],
      # Ledger metrics
      [
        {
          type   = "metric"
          x      = 0
          y      = 21 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Ledger Age (seconds)"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "rippled", "rippled_ledger_age", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 21 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Ledger Sequence"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "rippled", "rippled_ledger_seq", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
            yAxis  = { left = { showUnits = false } }
          }
        }
      ],
      # Consensus metrics
      [
        {
          type   = "metric"
          x      = 0
          y      = 27 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Last Close Converge Time (seconds)"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "rippled", "rippled_last_close_converge_time", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 27 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Last Close Proposers"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "rippled", "rippled_last_close_proposers", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        }
      ],
      # Load and IO
      [
        {
          type   = "metric"
          x      = 0
          y      = 33 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Load Factor"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "rippled", "rippled_load_factor", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 33 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "IO Latency (ms)"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "rippled", "rippled_io_latency_ms", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        }
      ],
      # EC2 CPU
      [
        {
          type   = "metric"
          x      = 0
          y      = 39 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "CPU Utilization %"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "AWS/EC2", "CPUUtilization", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 39 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Memory Used %"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "CWAgent", "mem_used_percent", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        }
      ],
      # Network
      [
        {
          type   = "metric"
          x      = 0
          y      = 45 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Network In (bytes)"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "AWS/EC2", "NetworkIn", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 45 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Network Out (bytes)"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "AWS/EC2", "NetworkOut", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        }
      ],
      # Disk
      [
        {
          type   = "metric"
          x      = 0
          y      = 51 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Disk Used % (NVMe /var/lib/rippled)"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "CWAgent", "disk_used_percent", "InstanceId", node.id, "path", "/var/lib/rippled", "device", "nvme1n1", "fstype", "xfs", merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 51 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Disk Used % (root /)"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "CWAgent", "disk_used_percent", "InstanceId", node.id, "path", "/", "device", "nvme0n1p1", "fstype", "xfs", merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        }
      ],
      # Swap and Peer Disconnects
      [
        {
          type   = "metric"
          x      = 0
          y      = 57 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Swap Used %"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "CWAgent", "swap_used_percent", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 57 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Peer Disconnects"
            region = var.region
            metrics = [
              for name, node in local.all_instances : [
                "rippled", "rippled_peer_disconnects", "InstanceId", node.id, merge({ label = name }, node.region != var.region ? { region = node.region } : {})
              ]
            ]
            stat   = "Average"
            period = 60
          }
        }
      ],
      # Validator Stats (from XRPL data API)
      [
        {
          type   = "metric"
          x      = 0
          y      = 63 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Validator Agreement Score %"
            region = var.region
            metrics = [
              ["rippled", "validator_agreement_1h", "InstanceId", aws_instance.node[local.validator.name].id, { label = "1 hour" }],
              ["rippled", "validator_agreement_24h", "InstanceId", aws_instance.node[local.validator.name].id, { label = "24 hours" }],
              ["rippled", "validator_agreement_30d", "InstanceId", aws_instance.node[local.validator.name].id, { label = "30 days" }]
            ]
            stat   = "Average"
            period = 180
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 63 + local.dashboard_y_offset
          width  = 12
          height = 6
          properties = {
            title  = "Validator Missed Validations"
            region = var.region
            metrics = [
              ["rippled", "validator_missed_1h", "InstanceId", aws_instance.node[local.validator.name].id, { label = "1 hour" }],
              ["rippled", "validator_missed_24h", "InstanceId", aws_instance.node[local.validator.name].id, { label = "24 hours" }]
            ]
            stat   = "Maximum"
            period = 180
            annotations = {
              horizontal = [
                { label = "Hourly threshold", value = local.validator_miss_hourly_threshold, color = "#ff7f0e" },
                { label = "Daily threshold", value = local.validator_miss_daily_threshold, color = "#d62728" }
              ]
            }
          }
        }
      ]
    )
  })
}

resource "aws_cloudwatch_log_group" "rippled_server_info" {
  for_each = local.regions

  region            = each.key
  name              = "/rippled/${var.environment}/server-info"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_stream" "rippled" {
  for_each       = aws_instance.node
  region         = local.node_region[each.key]
  name           = each.value.id
  log_group_name = aws_cloudwatch_log_group.rippled_server_info[local.node_region[each.key]].name
}

# Migration artifact: both existing stacks are single-region ap-south-1;
# remove once all stacks have applied the for_each change.
moved {
  from = aws_cloudwatch_log_group.rippled_server_info
  to   = aws_cloudwatch_log_group.rippled_server_info["ap-south-1"]
}
