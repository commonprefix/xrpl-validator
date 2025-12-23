locals {
  all_instances = { for name, instance in aws_instance.node : name => instance.id }
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
          height = 3
          properties = {
            title  = "Alarm Status"
            alarms = concat(
              [for name, _ in aws_instance.node : aws_cloudwatch_metric_alarm.server_state[name].arn],
              [for name, _ in aws_instance.node : aws_cloudwatch_metric_alarm.ledger_age[name].arn],
              [for name, _ in aws_instance.node : aws_cloudwatch_metric_alarm.peer_count[name].arn],
              [for name, _ in aws_instance.node : aws_cloudwatch_metric_alarm.cluster_count[name].arn],
              [for name, _ in aws_instance.node : aws_cloudwatch_metric_alarm.needs_reboot[name].arn]
            )
          }
        }
      ],
      # Server Info from Logs
      [
        {
          type   = "log"
          x      = 0
          y      = 3
          width  = 24
          height = 6
          properties = {
            title  = "Server Info (Latest) - ${var.region}"
            region = var.region
            query  = "SOURCE '/rippled/server-info' | fields @timestamp, instance_id, public_ip, build_version, server_state, pubkey_node, pubkey_validator, complete_ledgers, ledger_hash | sort @timestamp desc | dedup instance_id"
          }
        }
      ],
      # Server State and Uptime
      [
        {
          type   = "metric"
          x      = 0
          y      = 9
          width  = 12
          height = 6
          properties = {
            title  = "Server State (5=proposing, 4=full)"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "rippled", "rippled_server_state", "InstanceId", id, { label = name }
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 9
          width  = 12
          height = 6
          properties = {
            title  = "Uptime (hours)"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "rippled", "rippled_uptime", "InstanceId", id, { label = name }
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
          y      = 15
          width  = 12
          height = 6
          properties = {
            title  = "Peer Count"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "rippled", "rippled_peers", "InstanceId", id, { label = name }
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 15
          width  = 12
          height = 6
          properties = {
            title  = "Cluster Count"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "rippled", "rippled_cluster_count", "InstanceId", id, { label = name }
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
          y      = 21
          width  = 12
          height = 6
          properties = {
            title  = "Ledger Age (seconds)"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "rippled", "rippled_ledger_age", "InstanceId", id, { label = name }
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 21
          width  = 12
          height = 6
          properties = {
            title  = "Ledger Sequence"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "rippled", "rippled_ledger_seq", "InstanceId", id, { label = name }
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
          y      = 27
          width  = 12
          height = 6
          properties = {
            title  = "Last Close Converge Time (seconds)"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "rippled", "rippled_last_close_converge_time", "InstanceId", id, { label = name }
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 27
          width  = 12
          height = 6
          properties = {
            title  = "Last Close Proposers"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "rippled", "rippled_last_close_proposers", "InstanceId", id, { label = name }
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
          y      = 33
          width  = 12
          height = 6
          properties = {
            title  = "Load Factor"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "rippled", "rippled_load_factor", "InstanceId", id, { label = name }
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 33
          width  = 12
          height = 6
          properties = {
            title  = "IO Latency (ms)"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "rippled", "rippled_io_latency_ms", "InstanceId", id, { label = name }
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
          y      = 39
          width  = 12
          height = 6
          properties = {
            title  = "CPU Utilization %"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "AWS/EC2", "CPUUtilization", "InstanceId", id, { label = name }
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 39
          width  = 12
          height = 6
          properties = {
            title  = "Memory Used %"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "CWAgent", "mem_used_percent", "InstanceId", id, { label = name }
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
          y      = 45
          width  = 12
          height = 6
          properties = {
            title  = "Network In (bytes)"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "AWS/EC2", "NetworkIn", "InstanceId", id, { label = name }
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 45
          width  = 12
          height = 6
          properties = {
            title  = "Network Out (bytes)"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "AWS/EC2", "NetworkOut", "InstanceId", id, { label = name }
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
          y      = 51
          width  = 12
          height = 6
          properties = {
            title  = "Disk Used % (NVMe /var/lib/rippled)"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "CWAgent", "disk_used_percent", "InstanceId", id, "path", "/var/lib/rippled", "device", "nvme1n1", "fstype", "xfs", { label = name }
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 51
          width  = 12
          height = 6
          properties = {
            title  = "Disk Used % (root /)"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "CWAgent", "disk_used_percent", "InstanceId", id, "path", "/", "device", "nvme0n1p1", "fstype", "xfs", { label = name }
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
          y      = 57
          width  = 12
          height = 6
          properties = {
            title  = "Swap Used %"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "CWAgent", "swap_used_percent", "InstanceId", id, { label = name }
              ]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 57
          width  = 12
          height = 6
          properties = {
            title  = "Peer Disconnects"
            region = var.region
            metrics = [
              for name, id in local.all_instances : [
                "rippled", "rippled_peer_disconnects", "InstanceId", id, { label = name }
              ]
            ]
            stat   = "Average"
            period = 60
          }
        }
      ]
    )
  })
}

resource "aws_cloudwatch_log_group" "rippled_server_info" {
  name              = "/rippled/server-info"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_stream" "rippled" {
  for_each       = aws_instance.node
  name           = each.value.id
  log_group_name = aws_cloudwatch_log_group.rippled_server_info.name
}
