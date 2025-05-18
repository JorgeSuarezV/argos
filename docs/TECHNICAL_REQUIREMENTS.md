# Argos - Technical Requirements

## System Architecture

### Core Components
1. **Core System**
   - Implemented as a supervisor tree in Elixir
   - Responsible for system initialization and coordination
   - Must handle graceful startup and shutdown
   - Must support hot code reloading through CLI commands:
     - `argos create <resource_type> <resource_name>`
     - `argos update <resource_type> <resource_name>`
     - `argos delete <resource_type> <resource_name>`
   - Resource types include: monitor, rule, action, system_config

2. **Monitor System**
   - Must implement a common interface for all monitors
   - Must support the following monitor types:
     - HTTP Monitor
     - WebSocket Monitor
     - MQTT Monitor
   - Each monitor must:
     - Normalize incoming data
     - Support configurable data transformation
     - Implement error handling and recovery
     - Support connection retry mechanisms
     - Maintain a state store accessible to rules and actions
     - Provide data access methods for rules and actions
     - Each monitor must implement its own configurable retry policy (exponential backoff, max retries, timeout, etc.)

3. **Condition Evaluation System**
   - Must support complex logical expressions
   - Must implement a rule engine for condition evaluation
   - Must support:
     - Boolean operations (AND, OR, NOT)
     - Comparison operators
     - Mathematical operations
     - Custom function evaluation
   - Rules must have access to:
     - Monitor state and historical data
     - System metrics and status
     - Other rules' evaluation results
   - Rules must be able to:
     - Query monitor data using a standardized interface
     - Access historical data within configurable time windows
     - Combine data from multiple monitors

4. **Action System**
   - Must implement a common interface for all actions
   - Must support the following action types:
     - Email sending
     - HTTP requests
     - Database operations
     - Report generation
   - Each action must:
     - Support retry mechanisms
     - Implement error handling
     - Support async execution
     - Provide execution status feedback
     - Have access to:
       - Monitor data that triggered the action
       - Rule evaluation results
       - System state and metrics
       - Historical data

### Configuration System

1. **Configuration File Structure**
   ```jsonc
   {
     "system": {
       "name": "argos",
       "version": "1.0.0",
       "environment": "production",
       "log_level": "debug",
       "max_retries": 3,
       "timeout": 5000
     },
     "parameters": {
       "iot_token": "ABC123",
       "admin_email": "admin@example.com",
       "alert_cc": ["ops@example.com", "dev@example.com"]
     },
     "monitors": {
       "single": [
         {
           "name": "http_monitor_1",
           "type": "http",
           "config": {
             "url": "https://api.example.com/data",
             "method": "GET",
             "headers": {
               "Authorization": "Bearer ${parameters.iot_token}",
               "Accept": "application/json"
             },
             "interval": 10000,
             "timeout": 3000,
             "follow_redirect": true,
             "verify_ssl": true,
             "request_body": null
           },
           "retry_policy": {
             "max_retries": 5,
             "backoff_strategy": "exponential",
             "retry_timeout": 2000
           }
         },
         {
           "name": "mqtt_monitor_1",
           "type": "mqtt",
           "config": {
             "broker_url": "mqtt://broker.example.com:1883",
             "topic": "sensors/temperature",
             "qos": 1,
             "client_id": "argos_mqtt_1",
             "username": "user",
             "password": "pass",
             "keepalive": 60,
             "clean_session": true,
             "reconnect_interval": 5000
           },
           "retry_policy": {
             "max_retries": 10,
             "backoff_strategy": "linear",
             "retry_timeout": 1000
           }
         },
         {
           "name": "websocket_monitor_1",
           "type": "websocket",
           "config": {
             "url": "ws://ws.example.com/socket",
             "protocols": ["json"],
             "headers": {
               "Authorization": "Bearer ${parameters.iot_token}"
             },
             "ping_interval": 30000,
             "reconnect": true
           },
           "retry_policy": {
             "max_retries": 3,
             "backoff_strategy": "exponential",
             "retry_timeout": 5000
           }
         }
       ],
       "bulk": [
         {
           "name_pattern": "iot_http_monitor_{i}",
           "type": "http",
           "config": {
             "url": [
               "http://iot-device-1.local/data",
               "http://iot-device-2.local/data"
             ],
             "method": "GET",
             "headers": {
               "Authorization": "Bearer ${parameters.iot_token}"
             },
             "interval": 10000,
             "timeout": 3000
           },
           "retry_policy": {
             "max_retries": 5,
             "backoff_strategy": "exponential",
             "retry_timeout": 2000
           }
         }
       ]
     },
     "actions": {
       "single": [
         {
           "name": "send_email_alert",
           "type": "email",
           "config": {
             "to": "${parameters.admin_email}",
             "cc": "${parameters.alert_cc}",
             "bcc": [],
             "subject": "Alert: Condition triggered",
             "body": "<b>Alert details:</b> ${rule.details}",
             "is_html": true,
             "attachments": [],
             "smtp_server": "smtp.example.com",
             "smtp_port": 587,
             "smtp_username": "smtp_user",
             "smtp_password": "smtp_pass",
             "from": "argos@example.com"
           },
           "retry_policy": {
             "max_retries": 2,
             "backoff_strategy": "fixed",
             "retry_timeout": 10000
           }
         },
         {
           "name": "http_callback",
           "type": "http",
           "config": {
             "url": "https://hooks.example.com/notify",
             "method": "POST",
             "headers": {
               "Content-Type": "application/json"
             },
             "body_template": "{\"event\": \"${rule.name}\", \"data\": ${monitor.data}}",
             "timeout": 2000,
             "verify_ssl": true
           },
           "retry_policy": {
             "max_retries": 3,
             "backoff_strategy": "exponential",
             "retry_timeout": 3000
           }
         },
         {
           "name": "db_write",
           "type": "database",
           "config": {
             "db_type": "postgres",
             "host": "db.example.com",
             "port": 5432,
             "database": "argos",
             "username": "argos_user",
             "password": "argos_pass",
             "table": "events",
             "insert_template": {
               "event": "${rule.name}",
               "timestamp": "${system.timestamp}",
               "payload": "${monitor.data}"
             }
           },
           "retry_policy": {
             "max_retries": 5,
             "backoff_strategy": "exponential",
             "retry_timeout": 2000
           }
         }
       ],
       "bulk": [
         {
           "name_pattern": "send_bulk_email_{i}",
           "type": "email",
           "config": {
             "to": [
               "user1@example.com",
               "user2@example.com"
             ],
             "cc": [],
             "bcc": [],
             "subject": "Bulk Alert",
             "body": "Bulk alert details",
             "is_html": true,
             "attachments": [],
             "smtp_server": "smtp.example.com",
             "smtp_port": 587,
             "smtp_username": "smtp_user",
             "smtp_password": "smtp_pass",
             "from": "argos@example.com"
           },
           "bulk_field": "to",
           "retry_policy": {
             "max_retries": 2,
             "backoff_strategy": "fixed",
             "retry_timeout": 10000
           }
         }
       ]
     },
     "rules": [
       {
         "name": "high_temp_or_slow_response",
         "description": "Trigger if temperature is high or HTTP response is slow",
         "monitor": ["http_monitor_1", "mqtt_monitor_1"],
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
         },
         "actions": ["send_email_alert", "http_callback"],
         "cooldown": 300,
         "parameters": {
           "threshold": 80
         }
       }
     ]
   }
   ```

2. **Configuration Management**
   - Support for JSON configuration files
   - Hot reloading through CLI commands
   - Configuration validation on load
   - Environment-specific configurations
   - Configuration versioning
   - Backup and restore capabilities

3. **CLI Interface**
   - Resource management commands:
     ```
     argos create monitor http_monitor_1 --config config.json
     argos update rule high_traffic_rule --config config.json
     argos delete action send_alert
     ```
   - System management commands:
     ```
     argos status
     argos reload
     argos validate-config
     argos backup
     argos restore
     ```

### Technical Specifications

1. **Programming Language & Framework**
   - Primary Language: Elixir
   - Minimum Elixir Version: 1.14.0
   - OTP Version: 25.0 or higher

2. **Dependencies**
   - HTTP Client: Tesla or HTTPoison
   - WebSocket: WebSockex
   - Database: Ecto (for database actions)
   - Email: Swoosh
   - Configuration: Config

3. **Performance Requirements**
   - Must handle at least 1000 events per second
   - Maximum latency for condition evaluation: 100ms
   - Maximum latency for action execution: 500ms
   - Memory usage should not exceed 1GB under normal operation

4. **Reliability Requirements**
   - System uptime: 99.9%
   - Automatic recovery from crashes
   - Data persistence for critical operations
   - Logging of all system events

5. **Security Requirements**
   - Secure storage of credentials
   - Support for TLS/SSL
   - Input validation and sanitization
   - Rate limiting for external connections

6. **Monitoring & Logging**
   - Structured logging using Logger
   - Metrics collection using Telemetry
   - Health check endpoints
   - Performance monitoring

7. **Configuration System**
   - Support for JSON configuration
   - Hot reloading of configuration
   - Environment-based configuration
   - Validation of configuration schema
   - Each monitor's retry policy must be configurable in the system configuration (e.g., max_retries, backoff_strategy, retry_timeout)

8. **Testing Requirements**
   - Unit test coverage: > 80%
   - Integration tests for all components
   - Property-based testing for critical paths
   - Performance testing suite

9. **Documentation Requirements**
   - API documentation using ExDoc
   - Configuration examples
   - Architecture diagrams
   - Deployment guides

10. **Deployment Requirements**
    - Support for Docker containers
    - Release management using Mix releases
    - Configuration for different environments
    - Health check endpoints

## Future Technical Considerations

1. **Distributed System Support**
   - Node discovery
   - Distributed condition evaluation
   - Cluster management
   - Data replication

2. **Event Storage**
   - Time-series database integration
   - Event persistence
   - Historical data analysis
   - Data retention policies

3. **Visual Editor Integration**
   - REST API for configuration
   - WebSocket support for real-time updates
   - Configuration validation endpoints
   - User authentication and authorization

4. **Monitoring Integration**
   - Prometheus metrics
   - Grafana dashboards
   - Alert manager integration
   - Custom metric collection 