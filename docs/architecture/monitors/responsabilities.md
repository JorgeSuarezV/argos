# Argos Monitor System Architecture

## System Overview

The Argos Monitor System is designed as an extensible architecture for protocol monitoring, with a strong focus on data normalization and protocol independence. The system uses interfaces to ensure consistent behavior and easy protocol extension.

## Core Components

### 1. MonitorSupervisor
- **Type**: Dynamic Supervisor
- **Purpose**: Manages the lifecycle of all monitor instances
- **Responsibilities**:
  - Dynamic supervision of monitor processes
  - Lifecycle management (start/stop/restart)
  - Process isolation and crash recovery
  - Resource allocation and cleanup
  - Register and initialize all monitors

### 2. BaseMonitor
- **Type**: GenServer
- **Purpose**: Provides common functionality for all monitors
- **Interface**: MonitorInterface
- **Responsibilities**:
  - Common monitor behavior implementation
  - Health check execution
  - Protocol-agnostic monitoring logic
  - Monitor lifecycle hooks

### 3. Protocol Monitors

#### Protocol Interface
```elixir
defprotocol Argos.Monitors.ProtocolInterface do
  @doc "Establishes connection to the protocol endpoint"
  def connect(config)
  
  @doc "Terminates connection to the protocol endpoint"
  def disconnect(config)
  
  @doc "Handles incoming protocol messages"
  def handle_message(message, state)
  
  @doc "Returns current protocol connection status"
  def get_status(state)
  
  @doc "Returns protocol-specific metrics"
  def get_metrics(state)
end
```

#### HTTP Monitor
- **Type**: GenServer
- **Purpose**: Monitors HTTP endpoints
- **Interface**: ProtocolInterface
- **Configuration**:
  ```json
  {
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
  }
  ```

#### MQTT Monitor
- **Type**: GenServer
- **Purpose**: Monitors MQTT topics
- **Interface**: ProtocolInterface
- **Configuration**:
  ```json
  {
    "broker_url": "mqtt://broker.example.com:1883",
    "topic": "sensors/temperature",
    "qos": 1,
    "client_id": "argos_mqtt_1",
    "username": "user",
    "password": "pass",
    "keepalive": 60,
    "clean_session": true,
    "reconnect_interval": 5000
  }
  ```

#### WebSocket Monitor
- **Type**: GenServer
- **Purpose**: Monitors WebSocket connections
- **Interface**: ProtocolInterface
- **Configuration**:
  ```json
  {
    "url": "ws://ws.example.com/socket",
    "protocols": ["json"],
    "headers": {
      "Authorization": "Bearer ${parameters.iot_token}"
    },
    "ping_interval": 30000,
    "reconnect": true
  }
  ```

### 4. Normalize
- **Type**: Module
- **Purpose**: Standardizes all monitor data
- **Interface**: NormalizationInterface
- **Responsibilities**:
  - Data format standardization
  - Metadata injection
  - Timestamp management
  - Field validation
  - Format versioning
- **Normalized Data Format**:
  ```elixir
  %{
    monitor_id: String.t(),         # Required, unique per monitor instance
    timestamp: DateTime.t(),        # Always present, UTC ISO8601
    status: atom(),                 # Required, e.g. :ok, :error, :timeout
    data: map() | nil,              # Normalized, protocol-agnostic result
    error: map() | nil,             # Normalized error info, if any
    meta: map()                     # Open for extension: retry_count, latency, etc.
  }
  ```

### 5. ErrorHandler
- **Type**: GenServer
- **Purpose**: Centralizes error handling
- **Responsibilities**:
  - Error classification and categorization
  - Error recovery strategy execution
  - Error logging and monitoring
  - Error metrics collection
  - Error notification routing

### 6. StateManager
- **Type**: GenServer
- **Purpose**: Manages monitor state
- **Responsibilities**:
  - Monitor state persistence
  - State versioning
  - State consistency validation
  - State access control
  - State history management

### 7. ConnectionManager
- **Type**: GenServer
- **Purpose**: Manages protocol connections
- **Responsibilities**:
  - Connection pool management
  - Connection lifecycle
  - Connection state tracking
  - Connection metrics
  - Connection recovery

## Data Flow

1. **Protocol Data Collection**:
   - Protocol monitors collect raw data
   - Data is passed to Normalize module
   - Normalize standardizes data format
   - Normalized data flows to other components

2. **Normalization Process**:
   ```
   Raw Protocol Data -> Normalize -> Standardized Data
   ```
   - All protocol-specific data is converted to standard format
   - Metadata is injected
   - Timestamps are standardized
   - Validation is performed

3. **Post-Normalization Flow**:
   ```
   Standardized Data -> StateManager (state updates)
                    -> ErrorHandler (if errors)
                    -> Other Components
   ```

## Extending the System

### Adding New Protocols

1. **Implement Protocol Interface**:
   ```elixir
   defmodule Argos.Monitors.NewProtocolMonitor do
     use GenServer
     @behaviour Argos.Monitors.ProtocolInterface
     
     # Implement interface callbacks
     def connect(config), do: ...
     def disconnect(config), do: ...
     def handle_message(message, state), do: ...
     def get_status(state), do: ...
     def get_metrics(state), do: ...
   end
   ```

2. **Configuration**:
   - Add protocol-specific configuration schema
   - Define default values
   - Document configuration options

3. **Integration**:
   # Argos Monitor System Architecture

## System Overview

The Argos Monitor System is designed as an extensible architecture for protocol monitoring, with a strong focus on data normalization and protocol independence. The system uses interfaces to ensure consistent behavior and easy protocol extension.

## Core Components

### 1. MonitorSupervisor
- **Type**: Dynamic Supervisor
- **Purpose**: Manages the lifecycle of all monitor instances
- **Responsibilities**:
  - Dynamic supervision of monitor processes
  - Lifecycle management (start/stop/restart)
  - Process isolation and crash recovery
  - Resource allocation and cleanup

### 2. BaseMonitor
- **Type**: GenServer
- **Purpose**: Provides common functionality for all monitors
- **Interface**: MonitorInterface
- **Responsibilities**:
  - Common monitor behavior implementation
  - Protocol-agnostic monitoring logic
  - Monitor lifecycle hooks

### 3. Protocol Monitors

#### Protocol Interface
```elixir
defprotocol Argos.Monitors.ProtocolInterface do
  @doc "Establishes connection to the protocol endpoint"
  def connect(config)
  
  @doc "Terminates connection to the protocol endpoint"
  def disconnect(config)
  
  @doc "Handles incoming protocol messages"
  def handle_message(message, state)
  
  @doc "Returns current protocol connection status"
  def get_status(state)
  
  @doc "Returns protocol-specific metrics"
  def get_metrics(state)
end
```

#### HTTP Monitor
- **Type**: GenServer
- **Purpose**: Monitors HTTP endpoints
- **Interface**: ProtocolInterface
- **Configuration**:
  ```json
  {
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
  }
  ```

#### MQTT Monitor
- **Type**: GenServer
- **Purpose**: Monitors MQTT topics
- **Interface**: ProtocolInterface
- **Configuration**:
  ```json
  {
    "broker_url": "mqtt://broker.example.com:1883",
    "topic": "sensors/temperature",
    "qos": 1,
    "client_id": "argos_mqtt_1",
    "username": "user",
    "password": "pass",
    "keepalive": 60,
    "clean_session": true,
    "reconnect_interval": 5000
  }
  ```

#### WebSocket Monitor
- **Type**: GenServer
- **Purpose**: Monitors WebSocket connections
- **Interface**: ProtocolInterface
- **Configuration**:
  ```json
  {
    "url": "ws://ws.example.com/socket",
    "protocols": ["json"],
    "headers": {
      "Authorization": "Bearer ${parameters.iot_token}"
    },
    "ping_interval": 30000,
    "reconnect": true
  }
  ```

### 4. Normalize
- **Type**: Module
- **Purpose**: Standardizes all monitor data
- **Interface**: NormalizationInterface
- **Responsibilities**:
  - Data format standardization
  - Metadata injection
  - Timestamp management
  - Field validation
  - Format versioning
- **Normalized Data Format**:
  ```elixir
  %{
    monitor_id: String.t(),         # Required, unique per monitor instance
    timestamp: DateTime.t(),        # Always present, UTC ISO8601
    status: atom(),                 # Required, e.g. :ok, :error, :timeout
    data: map() | nil,              # Normalized, protocol-agnostic result
    error: map() | nil,             # Normalized error info, if any
    meta: map()                     # Open for extension: retry_count, latency, etc.
  }
  ```

### 5. ErrorHandler
- **Type**: GenServer
- **Purpose**: Centralizes error handling
- **Responsibilities**:
  - Error classification and categorization
  - Error recovery strategy execution
  - Error logging and monitoring
  - Error metrics collection
  - Error notification routing

### 6. StateManager
- **Type**: GenServer
- **Purpose**: Manages monitor state
- **Responsibilities**:
  - Monitor state persistence
  - State versioning
  - State consistency validation
  - State access control
  - State history management


## Data Flow

1. **Protocol Data Collection**:
   - Protocol monitors collect raw data
   - Data is passed to Normalize module
   - Normalize standardizes data format
   - Normalized data flows to other components

2. **Normalization Process**:
   ```
   Raw Protocol Data -> Normalize -> Standardized Data
   ```
   - All protocol-specific data is converted to standard format
   - Metadata is injected
   - Timestamps are standardized
   - Validation is performed

3. **Post-Normalization Flow**:
   ```
   Standardized Data -> StateManager (state updates)
                    -> ErrorHandler (if errors)
                    -> Other Components
   ```

## Extending the System

### Adding New Protocols

1. **Implement Protocol Interface**:
   ```elixir
   defmodule Argos.Monitors.NewProtocolMonitor do
     use GenServer
     @behaviour Argos.Monitors.ProtocolInterface
     
     # Implement interface callbacks
     def connect(config), do: ...
     def disconnect(config), do: ...
     def handle_message(message, state), do: ...
     def get_status(state), do: ...
     def get_metrics(state), do: ...
   end
   ```

2. **Configuration**:
   - Add protocol-specific configuration schema
   - Define default values
   - Document configuration options

3. **Integration**:
   - Register with MonitorSupervisor
   - Implement protocol-specific connection handling
   - Ensure data is properly normalized

## Performance Considerations

- System designed to handle 1000+ events per second
- Maximum latency for condition evaluation: 100ms
- Maximum latency for action execution: 500ms
- Memory usage target: < 1GB under normal operation# Argos Monitor System Architecture

## System Overview

The Argos Monitor System is designed as an extensible architecture for protocol monitoring, with a strong focus on data normalization and protocol independence. The system uses interfaces to ensure consistent behavior and easy protocol extension.

## Core Components

### 1. MonitorSupervisor
- **Type**: Dynamic Supervisor
- **Purpose**: Manages the lifecycle of all monitor instances
- **Responsibilities**:
  - Dynamic supervision of monitor processes
  - Lifecycle management (start/stop/restart)
  - Process isolation and crash recovery
  - Resource allocation and cleanup

### 2. BaseMonitor
- **Type**: GenServer
- **Purpose**: Provides common functionality for all monitors
- **Interface**: MonitorInterface
- **Responsibilities**:
  - Common monitor behavior implementation
  - Health check execution
  - Basic state tracking
  - Protocol-agnostic monitoring logic
  - Monitor lifecycle hooks

### 3. Protocol Monitors

#### Protocol Interface
```elixir
defprotocol Argos.Monitors.ProtocolInterface do
  @doc "Establishes connection to the protocol endpoint"
  def connect(config)
  
  @doc "Terminates connection to the protocol endpoint"
  def disconnect(config)
  
  @doc "Handles incoming protocol messages"
  def handle_message(message, state)
  
  @doc "Returns current protocol connection status"
  def get_status(state)
  
  @doc "Returns protocol-specific metrics"
  def get_metrics(state)
end
```

#### HTTP Monitor
- **Type**: GenServer
- **Purpose**: Monitors HTTP endpoints
- **Interface**: ProtocolInterface
- **Configuration**:
  ```json
  {
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
  }
  ```

#### MQTT Monitor
- **Type**: GenServer
- **Purpose**: Monitors MQTT topics
- **Interface**: ProtocolInterface
- **Configuration**:
  ```json
  {
    "broker_url": "mqtt://broker.example.com:1883",
    "topic": "sensors/temperature",
    "qos": 1,
    "client_id": "argos_mqtt_1",
    "username": "user",
    "password": "pass",
    "keepalive": 60,
    "clean_session": true,
    "reconnect_interval": 5000
  }
  ```

#### WebSocket Monitor
- **Type**: GenServer
- **Purpose**: Monitors WebSocket connections
- **Interface**: ProtocolInterface
- **Configuration**:
  ```json
  {
    "url": "ws://ws.example.com/socket",
    "protocols": ["json"],
    "headers": {
      "Authorization": "Bearer ${parameters.iot_token}"
    },
    "ping_interval": 30000,
    "reconnect": true
  }
  ```

### 4. Normalize
- **Type**: Module
- **Purpose**: Standardizes all monitor data
- **Interface**: NormalizationInterface
- **Responsibilities**:
  - Data format standardization
  - Metadata injection
  - Timestamp management
  - Field validation
  - Format versioning
- **Normalized Data Format**:
  ```elixir
  %{
    monitor_id: String.t(),         # Required, unique per monitor instance
    timestamp: DateTime.t(),        # Always present, UTC ISO8601
    status: atom(),                 # Required, e.g. :ok, :error, :timeout
    data: map() | nil,              # Normalized, protocol-agnostic result
    error: map() | nil,             # Normalized error info, if any
    meta: map()                     # Open for extension: retry_count, latency, etc.
  }
  ```

### 5. ErrorHandler
- **Type**: GenServer
- **Purpose**: Centralizes error handling
- **Responsibilities**:
  - Error classification and categorization
  - Error recovery strategy execution
  - Error logging and monitoring
  - Error metrics collection
  - Error notification routing

### 6. StateManager
- **Type**: GenServer
- **Purpose**: Manages monitor state
- **Responsibilities**:
  - Monitor state persistence
  - State versioning
  - State consistency validation
  - State access control
  - State history management

### 7. ConnectionManager
- **Type**: GenServer
- **Purpose**: Manages protocol connections
- **Responsibilities**:
  - Connection pool management
  - Connection lifecycle
  - Connection state tracking
  - Connection metrics
  - Connection recovery

## Data Flow

1. **Protocol Data Collection**:
   - Protocol monitors collect raw data
   - Data is passed to Normalize module
   - Normalize standardizes data format
   - Normalized data flows to other components

2. **Normalization Process**:
   ```
   Raw Protocol Data -> Normalize -> Standardized Data
   ```
   - All protocol-specific data is converted to standard format
   - Metadata is injected
   - Timestamps are standardized
   - Validation is performed

3. **Post-Normalization Flow**:
   ```
   Standardized Data -> StateManager (state updates)
                    -> ErrorHandler (if errors)
                    -> Other Components
   ```

## Extending the System

### Adding New Protocols

1. **Implement Protocol Interface**:
   ```elixir
   defmodule Argos.Monitors.NewProtocolMonitor do
     use GenServer
     @behaviour Argos.Monitors.ProtocolInterface
     
     # Implement interface callbacks
     def connect(config), do: ...
     def disconnect(config), do: ...
     def handle_message(message, state), do: ...
     def get_status(state), do: ...
     def get_metrics(state), do: ...
   end
   ```

2. **Configuration**:
   - Add protocol-specific configuration schema
   - Define default values
   - Document configuration options

3. **Integration**:
   - Register with MonitorSupervisor
   - Implement protocol-specific connection handling
   - Ensure data is properly normalized

## Performance Considerations

- System designed to handle 1000+ events per second
- Maximum latency for condition evaluation: 100ms
- Maximum latency for action execution: 500ms
- Memory usage target: < 1GB under normal operation- Register with MonitorSupervisor
   - Implement protocol-specific connection handling
   - Ensure data is properly normalized

## Performance Considerations

- System designed to handle 1000+ events per second
- Maximum latency for condition evaluation: 100ms
- Maximum latency for action execution: 500ms
- Memory usage target: < 1GB under normal operation