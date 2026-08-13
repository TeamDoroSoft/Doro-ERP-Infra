resource "aws_sqs_queue" "dlq" {
  for_each = local.queue_names

  name                        = "${local.name_prefix}-alpha-${each.key}-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  message_retention_seconds   = 1209600
  sqs_managed_sse_enabled     = true
}

resource "aws_sqs_queue" "main" {
  for_each = local.queue_names

  name                        = "${local.name_prefix}-alpha-${each.key}.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  message_retention_seconds   = 1209600
  visibility_timeout_seconds  = 30
  receive_wait_time_seconds   = 20
  sqs_managed_sse_enabled     = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  for_each = local.queue_names

  queue_url = aws_sqs_queue.dlq[each.key].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main[each.key].arn]
  })
}

locals {
  sqs_send = {
    edge         = []
    store-access = ["audit-events"]
    commerce     = ["queue-events", "audit-events"]
    payment      = ["commerce-events", "audit-events"]
    queue        = ["audit-events"]
    audit        = []
  }

  sqs_receive = {
    edge         = []
    store-access = []
    commerce     = ["commerce-events"]
    payment      = []
    queue        = ["queue-events"]
    audit        = ["audit-events"]
  }
}
