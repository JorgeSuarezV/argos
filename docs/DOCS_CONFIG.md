# Argos Configuration Reference

This document explains each parameter and field in the Argos configuration JSON.

---

## Top-Level Structure
- **system**: General system settings.
- **parameters**: User-defined values for reuse and CLI/file injection.
- **monitors**: Monitoring definitions (single and bulk).
- **actions**: Action definitions (single and bulk).
- **rules**: Rule definitions for automation.

---

## 1. `system`
| Field         | Type    | Description |
|---------------|---------|-------------|
| name          | string  | Name of the Argos system instance. |
| version       | string  | Version of the configuration or system. |
| environment   | string  | Deployment environment (e.g., production, staging). |
| log_level     | string  | Logging verbosity (e.g., debug, info, warn, error). |
| max_retries   | int     | Default max retries for operations (can be overridden per monitor/action). |
| timeout       | int     | Default timeout in ms for operations. |

---

## 2. `parameters`
- Key-value pairs for reusable values.
- Can be injected from CLI or files if marked as such in the config.
- Example: `{ "iot_token": "ABC123" }`

---

## 3. `monitors`
### 3.1. `single`
- Array of individual monitor definitions.
- Each monitor has:
  - **name**: Unique string identifier.
  - **type**: One of `http`, `mqtt`, `websocket`, etc.
  - **config**: Type-specific settings (see below).
  - **retry_policy**: Retry settings for this monitor.

#### HTTP Monitor Config
| Field           | Type    | Description |
|-----------------|---------|-------------|
| url             | string  | Endpoint to poll. |
| method          | string  | HTTP method (GET, POST, etc.). |
| headers         | object  | HTTP headers. |
| interval        | int     | Polling interval in ms. |
| timeout         | int     | Request timeout in ms. |
| follow_redirect | bool    | Follow HTTP redirects. |
| verify_ssl      | bool    | Verify SSL certificates. |
| request_body    | string/null | Body for POST/PUT requests. |

#### MQTT Monitor Config
| Field           | Type    | Description |
|-----------------|---------|-------------|
| broker_url      | string  | MQTT broker address. |
| topic           | string  | Topic to subscribe to. |
| qos             | int     | Quality of Service (0, 1, 2). |
| client_id       | string  | MQTT client ID. |
| username        | string  | Username for broker. |
| password        | string  | Password for broker. |
| keepalive       | int     | Keepalive interval in seconds. |
| clean_session   | bool    | Clean session flag. |
| reconnect_interval | int  | Reconnect interval in ms. |

#### WebSocket Monitor Config
| Field           | Type    | Description |
|-----------------|---------|-------------|
| url             | string  | WebSocket endpoint. |
| protocols       | array   | Supported protocols. |
| headers         | object  | WebSocket headers. |
| ping_interval   | int     | Ping interval in ms. |
| reconnect       | bool    | Auto-reconnect flag. |

#### Retry Policy
| Field           | Type    | Description |
|-----------------|---------|-------------|
| max_retries     | int     | Maximum retry attempts. |
| backoff_strategy| string  | One of: `fixed`, `linear`, `exponential`. |
| retry_timeout   | int     | Initial retry delay in ms. |

### 3.2. `bulk`
- Array of bulk monitor definitions.
- **name_pattern**: Pattern for naming (e.g., `iot_http_monitor_{i}`).
- **config**: Same as single, but fields like `url` or `topic` can be arrays.
- **bulk_field** (optional): Which field to expand for bulk (default: first array field).
- System generates one monitor per value in the array.

---

## 4. `actions`
### 4.1. `single`
- Array of individual action definitions.
- Each action has:
  - **name**: Unique string identifier.
  - **type**: One of `email`, `http`, `database`, etc.
  - **config**: Type-specific settings (see below).
  - **retry_policy**: Retry settings for this action.

#### Email Action Config
| Field         | Type    | Description |
|---------------|---------|-------------|
| to            | array   | Recipients (one email sent to all). |
| cc            | array   | CC recipients. |
| bcc           | array   | BCC recipients. |
| subject       | string  | Email subject. |
| body          | string  | Email body (can use HTML if `is_html` is true). |
| is_html       | bool    | Whether body is HTML. |
| attachments   | array   | List of file paths. |
| smtp_server   | string  | SMTP server address. |
| smtp_port     | int     | SMTP port. |
| smtp_username | string  | SMTP username. |
| smtp_password | string  | SMTP password. |
| from          | string  | Sender address. |

#### HTTP Action Config
| Field         | Type    | Description |
|---------------|---------|-------------|
| url           | string  | Endpoint to call. |
| method        | string  | HTTP method. |
| headers       | object  | HTTP headers. |
| body_template | string  | Template for request body. |
| timeout       | int     | Request timeout in ms. |
| verify_ssl    | bool    | Verify SSL certificates. |

#### Database Action Config
| Field           | Type    | Description |
|-----------------|---------|-------------|
| db_type         | string  | Database type (e.g., `postgres`). |
| host            | string  | DB host. |
| port            | int     | DB port. |
| database        | string  | DB name. |
| username        | string  | DB user. |
| password        | string  | DB password. |
| table           | string  | Table to write to. |
| insert_template | object  | Template for row data. |

#### Retry Policy (same as monitors)

### 4.2. `bulk`
- Array of bulk action definitions.
- **name_pattern**: Pattern for naming (e.g., `send_bulk_email_{i}`).
- **config**: Same as single, but fields like `to` can be arrays.
- **bulk_field**: Which field to expand for bulk (e.g., `to`).
- System generates one action per value in the array.

---

## 5. `rules`
- Array of rule definitions.
- **name**: Unique string identifier.
- **description**: Human-readable description.
- **monitor**: List of monitor names this rule applies to, or a pattern (see below).
- **condition**: Logical expression (supports `and`, `or`, `not`, etc.).
- **actions**: List of action names to trigger, or a pattern (see below).
- **cooldown**: Minimum time between triggers (seconds).
- **parameters**: Rule-specific parameters.

#### Referencing Bulk Monitors/Actions
- You can reference all instances generated from a bulk definition using a pattern in the `monitor` or `actions` field.
- Use `*` as a wildcard to match all generated names from a `name_pattern`.
- Example: `"monitor": "iot_http_monitor_*"` applies the rule to all monitors named `iot_http_monitor_1`, `iot_http_monitor_2`, etc.
- Example: `"actions": "send_bulk_email_*"` applies the rule to all actions named `send_bulk_email_1`, `send_bulk_email_2`, etc.

#### Condition Example
```jsonc
"condition": {
  "or": [
    {
      "and": [
        {"field": "mqtt_monitor_1.payload.temperature", "op": ">", "value": 80},
        {"field": "mqtt_monitor_1.payload.status", "op": "==", "value": "ok"}
      ]
    },
    {
      "and": [
        {"field": "http_monitor_1.response_time", "op": ">", "value": 1000},
        {"field": "http_monitor_1.body.status", "op": "==", "value": "error"}
      ]
    }
  ]
}
```
- **field**: Path to value in monitor data.
- **op**: Operator (`==`, `!=`, `>`, `<`, `>=`, `<=`, `in`, etc.).
- **value**: Value to compare against.

---

## 6. Notes
- All fields support parameter substitution (e.g., `${parameters.iot_token}`).
- Bulk monitors/actions are expanded at load time.
- Enumerated fields (like `backoff_strategy`) must use one of the documented options.
- For email actions, `to` as an array in `single` means one email to all; in `bulk` with `bulk_field: "to"`, it means one email per recipient.

---

For further details, see the configuration examples in `TECHNICAL_REQUIREMENTS.md`. 