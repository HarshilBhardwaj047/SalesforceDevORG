// Pre-deployment hooks run before metadata is deployed.
// Use for: feature toggles off, freezing dependent automation, data prep.
// Remove this placeholder when you add real pre-deploy work.

System.debug('Pre-deployment hook executed at ' + DateTime.now().formatGmt('yyyy-MM-dd HH:mm:ss') + ' UTC');
