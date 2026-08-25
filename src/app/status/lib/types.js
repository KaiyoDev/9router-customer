/**
 * Type definitions for the Status page data layer.
 */

/**
 * @typedef {'operational' | 'degraded' | 'outage' | 'unknown'} ComponentStatus
 */

/**
 * @typedef {object} StatusComponent
 * @property {string} id
 * @property {string} name
 * @property {ComponentStatus} status
 * @property {string} description
 */

/**
 * @typedef {object} Incident
 * @property {string} id
 * @property {string} date
 * @property {string} title
 * @property {string} description
 * @property {'minor' | 'major' | 'critical'} severity
 * @property {string|null} resolvedAt
 */

/**
 * @typedef {object} MaintenanceWindow
 * @property {string} scheduledAt
 * @property {string} description
 * @property {boolean} ongoing
 */

/**
 * @typedef {object} UptimeData
 * @property {number} '24h'
 * @property {number} '7d'
 * @property {number} '30d'
 */

/**
 * @typedef {object} ProviderInfo
 * @property {string} id
 * @property {string} name
 * @property {string} category
 * @property {number} connections
 * @property {number} activeConnections
 * @property {ComponentStatus} status
 */

/**
 * @typedef {object} StatusData
 * @property {string} name
 * @property {string} version
 * @property {string} url
 * @property {ComponentStatus} status
 * @property {UptimeData} uptime
 * @property {StatusComponent[]} components
 * @property {{configured:number;active:number;categoryBreakdown:{api:number;free:number;oauth:number}}} providers
 * @property {{requests24h:number;requestChange:string|null}} usage
 * @property {Incident[]} incidents
 * @property {MaintenanceWindow|null} maintenance
 * @property {string} updatedAt
 */

export {};
