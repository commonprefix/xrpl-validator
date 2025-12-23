locals {
  nodes_by_name = { for node in var.nodes : node.name => node }

  validator = [for node in var.nodes : node if node.validator][0]

  node_count = length([for node in var.nodes : node if !node.validator])
}
