'use strict';

const express = require('express');
const router = express.Router();

// Helper: generate a realistic mock build
function makeBuild(jobName, number, { result, duration, timestamp }) {
  const durationMs = duration * 1000;
  return {
    _class: 'org.jenkinsci.plugins.workflow.job.WorkflowRun',
    actions: [
      {
        _class: 'hudson.model.CauseAction',
        causes: [
          {
            _class: 'hudson.model.Cause$UserIdCause',
            shortDescription: 'Started by user admin',
            userId: 'admin',
            userName: 'Admin',
          },
        ],
      },
    ],
    artifacts: [],
    building: false,
    description: null,
    displayName: `#${number}`,
    duration: durationMs,
    estimatedDuration: 180000,
    executor: null,
    fullDisplayName: `${jobName} #${number}`,
    id: String(number),
    keepLog: false,
    number,
    queueId: number + 1000,
    result,
    timestamp,
    url: `http://jenkins.example.com/job/${jobName}/${number}/`,
    changeSets: [
      {
        _class: 'hudson.plugins.git.GitChangeSetList',
        items: [
          {
            _class: 'hudson.plugins.git.GitChangeSet',
            affectedPaths: [`src/main/java/${jobName.replace(/-/g, '/')}/Application.java`],
            commitId: Math.random().toString(16).slice(2, 10),
            timestamp,
            author: {
              absoluteUrl: 'http://jenkins.example.com/user/devuser',
              fullName: 'Dev User',
            },
            authorEmail: 'devuser@example.com',
            comment: `fix: resolve issue in ${jobName} service\n`,
            date: new Date(timestamp).toISOString(),
            id: Math.random().toString(16).slice(2, 10),
            msg: `fix: resolve issue in ${jobName} service`,
            paths: [],
          },
        ],
        kind: 'git',
      },
    ],
    culprits: [],
  };
}

// Mock build data per job
const BUILD_DATA = {
  'payment-service': [
    { number: 42, result: 'SUCCESS', duration: 187, timestamp: Date.now() - 1 * 3600000 },
    { number: 41, result: 'SUCCESS', duration: 201, timestamp: Date.now() - 5 * 3600000 },
    { number: 40, result: 'FAILURE', duration: 93, timestamp: Date.now() - 12 * 3600000 },
    { number: 39, result: 'SUCCESS', duration: 195, timestamp: Date.now() - 24 * 3600000 },
    { number: 38, result: 'SUCCESS', duration: 178, timestamp: Date.now() - 48 * 3600000 },
  ],
  'order-service': [
    { number: 27, result: 'SUCCESS', duration: 142, timestamp: Date.now() - 2 * 3600000 },
    { number: 26, result: 'UNSTABLE', duration: 155, timestamp: Date.now() - 8 * 3600000 },
    { number: 25, result: 'SUCCESS', duration: 138, timestamp: Date.now() - 16 * 3600000 },
    { number: 24, result: 'SUCCESS', duration: 149, timestamp: Date.now() - 30 * 3600000 },
    { number: 23, result: 'FAILURE', duration: 61, timestamp: Date.now() - 52 * 3600000 },
  ],
  'inventory-service': [
    { number: 15, result: 'SUCCESS', duration: 213, timestamp: Date.now() - 3 * 3600000 },
    { number: 14, result: 'SUCCESS', duration: 198, timestamp: Date.now() - 10 * 3600000 },
    { number: 13, result: 'SUCCESS', duration: 205, timestamp: Date.now() - 20 * 3600000 },
    { number: 12, result: 'UNSTABLE', duration: 220, timestamp: Date.now() - 36 * 3600000 },
    { number: 11, result: 'SUCCESS', duration: 189, timestamp: Date.now() - 60 * 3600000 },
  ],
};

function getBuildsForJob(jobName) {
  return BUILD_DATA[jobName] || BUILD_DATA['payment-service'];
}

// GET /job/:jobName/api/json — job info + last 5 builds
router.get('/job/:jobName/api/json', (req, res) => {
  const { jobName } = req.params;
  const builds = getBuildsForJob(jobName);
  const latestBuild = builds[0];

  res.json({
    _class: 'org.jenkinsci.plugins.workflow.job.WorkflowJob',
    actions: [],
    description: `CI/CD pipeline for ${jobName}`,
    displayName: jobName,
    displayNameOrNull: null,
    fullDisplayName: jobName,
    fullName: jobName,
    name: jobName,
    url: `http://jenkins.example.com/job/${jobName}/`,
    buildable: true,
    builds: builds.map(b => ({
      _class: 'org.jenkinsci.plugins.workflow.job.WorkflowRun',
      number: b.number,
      url: `http://jenkins.example.com/job/${jobName}/${b.number}/`,
    })),
    color: latestBuild.result === 'SUCCESS' ? 'blue' : latestBuild.result === 'FAILURE' ? 'red' : 'yellow',
    firstBuild: { number: builds[builds.length - 1].number, url: `http://jenkins.example.com/job/${jobName}/${builds[builds.length - 1].number}/` },
    healthReport: [
      {
        description: 'Build stability: No recent builds failed.',
        iconClassName: 'icon-health-80plus',
        iconUrl: 'health-80plus.png',
        score: 80,
      },
    ],
    inQueue: false,
    keepDependencies: false,
    lastBuild: { number: latestBuild.number, url: `http://jenkins.example.com/job/${jobName}/${latestBuild.number}/` },
    lastCompletedBuild: { number: latestBuild.number, url: `http://jenkins.example.com/job/${jobName}/${latestBuild.number}/` },
    lastFailedBuild: null,
    lastStableBuild: { number: latestBuild.number, url: `http://jenkins.example.com/job/${jobName}/${latestBuild.number}/` },
    lastSuccessfulBuild: { number: latestBuild.number, url: `http://jenkins.example.com/job/${jobName}/${latestBuild.number}/` },
    lastUnstableBuild: null,
    lastUnsuccessfulBuild: null,
    nextBuildNumber: latestBuild.number + 1,
    property: [],
    queueItem: null,
    concurrentBuild: false,
    disabled: false,
    downstreamProjects: [],
    labelExpression: '',
    scm: { _class: 'hudson.plugins.git.GitSCM' },
    upstreamProjects: [],
  });
});

// GET /job/:jobName/:buildNumber/api/json — single build details
router.get('/job/:jobName/:buildNumber/api/json', (req, res) => {
  const { jobName, buildNumber } = req.params;
  const num = parseInt(buildNumber, 10);
  const builds = getBuildsForJob(jobName);
  const buildMeta = builds.find(b => b.number === num) || builds[0];

  res.json(makeBuild(jobName, buildMeta.number, buildMeta));
});

// GET /crumbIssuer/api/json — Jenkins CSRF crumb (some plugins request this)
router.get('/crumbIssuer/api/json', (req, res) => {
  res.json({
    _class: 'hudson.security.csrf.DefaultCrumbIssuer',
    crumb: 'mock-crumb-value-abc123',
    crumbRequestField: 'Jenkins-Crumb',
  });
});

module.exports = router;
