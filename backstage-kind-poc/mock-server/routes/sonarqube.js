'use strict';

const express = require('express');
const router = express.Router();

// Mock SonarQube metrics per project
const METRICS = {
  'payment-service': {
    bugs: '0',
    vulnerabilities: '2',
    code_smells: '14',
    coverage: '87.5',
    duplicated_lines_density: '3.2',
    ncloc: '4821',
    sqale_index: '42',
    sqale_rating: '1.0',
    reliability_rating: '1.0',
    security_rating: '2.0',
    alert_status: 'OK',
  },
  'order-service': {
    bugs: '1',
    vulnerabilities: '0',
    code_smells: '22',
    coverage: '74.3',
    duplicated_lines_density: '5.1',
    ncloc: '6234',
    sqale_index: '65',
    sqale_rating: '1.0',
    reliability_rating: '2.0',
    security_rating: '1.0',
    alert_status: 'OK',
  },
  'inventory-service': {
    bugs: '0',
    vulnerabilities: '0',
    code_smells: '8',
    coverage: '91.2',
    duplicated_lines_density: '1.8',
    ncloc: '3105',
    sqale_index: '18',
    sqale_rating: '1.0',
    reliability_rating: '1.0',
    security_rating: '1.0',
    alert_status: 'OK',
  },
};

function getMetrics(componentKey) {
  return METRICS[componentKey] || METRICS['payment-service'];
}

function formatMeasure(metric, value) {
  return {
    metric,
    value,
    bestValue: false,
  };
}

// GET /api/measures/component
router.get('/api/measures/component', (req, res) => {
  const componentKey = req.query.component || req.query.componentKey || 'payment-service';
  const metricsParam = req.query.metricKeys || req.query.metrics || '';
  const requestedMetrics = metricsParam
    ? metricsParam.split(',').map(m => m.trim())
    : [
        'bugs',
        'vulnerabilities',
        'code_smells',
        'coverage',
        'duplicated_lines_density',
        'ncloc',
        'sqale_index',
        'sqale_rating',
        'reliability_rating',
        'security_rating',
        'alert_status',
      ];

  const data = getMetrics(componentKey);
  const measures = requestedMetrics
    .filter(m => data[m] !== undefined)
    .map(m => formatMeasure(m, data[m]));

  res.json({
    component: {
      key: componentKey,
      name: componentKey.replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase()),
      qualifier: 'TRK',
      measures,
      language: 'java',
    },
    metrics: requestedMetrics.map(m => ({
      key: m,
      name: m.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase()),
      type: 'FLOAT',
      higherValuesAreBetter: m === 'coverage',
    })),
  });
});

// GET /api/qualitygates/project_status
router.get('/api/qualitygates/project_status', (req, res) => {
  const projectKey = req.query.projectKey || req.query.projectId || 'payment-service';
  const data = getMetrics(projectKey);

  res.json({
    projectStatus: {
      status: data.alert_status === 'OK' ? 'OK' : 'ERROR',
      conditions: [
        {
          status: 'OK',
          metricKey: 'new_reliability_rating',
          comparator: 'GT',
          periodIndex: 1,
          errorThreshold: '1',
          actualValue: '1',
        },
        {
          status: 'OK',
          metricKey: 'new_security_rating',
          comparator: 'GT',
          periodIndex: 1,
          errorThreshold: '1',
          actualValue: '1',
        },
        {
          status: 'OK',
          metricKey: 'new_maintainability_rating',
          comparator: 'GT',
          periodIndex: 1,
          errorThreshold: '1',
          actualValue: '1',
        },
        {
          status: parseFloat(data.coverage) >= 80 ? 'OK' : 'ERROR',
          metricKey: 'new_coverage',
          comparator: 'LT',
          periodIndex: 1,
          errorThreshold: '80',
          actualValue: data.coverage,
        },
        {
          status: parseFloat(data.duplicated_lines_density) <= 3 ? 'OK' : 'WARN',
          metricKey: 'new_duplicated_lines_density',
          comparator: 'GT',
          periodIndex: 1,
          errorThreshold: '3',
          actualValue: data.duplicated_lines_density,
        },
      ],
      periods: [
        {
          index: 1,
          mode: 'previous_version',
          date: new Date(Date.now() - 7 * 24 * 3600000).toISOString(),
          parameter: '',
        },
      ],
      ignoredConditions: false,
    },
  });
});

// GET /api/components/show
router.get('/api/components/show', (req, res) => {
  const component = req.query.component || req.query.key || 'payment-service';
  res.json({
    component: {
      organization: 'default-organization',
      key: component,
      name: component.replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase()),
      qualifier: 'TRK',
      visibility: 'public',
      lastAnalysisDate: new Date(Date.now() - 2 * 3600000).toISOString(),
      tags: ['java', 'spring-boot', 'microservice'],
      version: '1.4.2',
    },
  });
});

// GET /api/issues/search — for code quality breakdown
router.get('/api/issues/search', (req, res) => {
  const componentKeys = req.query.componentKeys || 'payment-service';
  res.json({
    total: 16,
    p: 1,
    ps: 100,
    paging: { pageIndex: 1, pageSize: 100, total: 16 },
    effortTotal: 250,
    issues: [
      {
        key: 'AYxxx1',
        rule: 'java:S1135',
        severity: 'INFO',
        component: componentKeys,
        project: componentKeys,
        line: 42,
        hash: 'abc123',
        textRange: { startLine: 42, endLine: 42, startOffset: 4, endOffset: 20 },
        flows: [],
        status: 'OPEN',
        message: "Complete the task associated to this \"TODO\" comment.",
        effort: '1min',
        debt: '1min',
        author: 'devuser@example.com',
        tags: ['bad-practice'],
        creationDate: new Date(Date.now() - 14 * 24 * 3600000).toISOString(),
        updateDate: new Date(Date.now() - 7 * 24 * 3600000).toISOString(),
        type: 'CODE_SMELL',
        scope: 'MAIN',
      },
    ],
    components: [
      {
        key: componentKeys,
        enabled: true,
        qualifier: 'TRK',
        name: componentKeys,
        longName: componentKeys,
      },
    ],
    rules: [],
    users: [],
    languages: [],
    facets: [],
  });
});

module.exports = router;
