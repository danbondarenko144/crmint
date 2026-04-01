# Copyright 2018 Google Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Insight module

Anonymously report backend usage.
"""

from __future__ import print_function

import json
import math
import os
import platform
import random
import time

import requests

DEFAULT_TRACKING_ID = "UA-127959147-2"


def get_crmint_version() -> str:
  return os.getenv('CRMINT_VERSION', 'unset')


class GAProvider(object):
  """Reports backend usage to Google Analytics."""
  URL = 'https://www.google-analytics.com/collect'

  def __init__(self):
    self.tracking_id = DEFAULT_TRACKING_ID
    self.os_name = platform.system()
    self.python_version = platform.python_version()
    self.app_version = get_crmint_version()
    self.config = self._load_insight_config()

  def _define_random_values(self, conf):
    if not conf.get('client_id', None):
      conf['client_id'] = int(math.floor(time.time() * random.random()))
    return conf

  def _load_insight_config(self):
    if 'REPORT_USAGE_ID' in os.environ:
      client_id = os.getenv('REPORT_USAGE_ID')
      opt_out = not bool(client_id)
      return {'client_id': client_id, 'opt_out': opt_out}
    else:
      return {}

  @property
  def client_id(self):
    return self.config.get('client_id', None)

  @property
  def opt_out(self):
    return self.config.get('opt_out', None)

  def _send(self, payload):
    now_ms = math.floor(time.time() * 1000)
    qs = {
      # GA Measurement Protocol API version
      'v': 1,

      # Hit type
      't': payload['type'],

      # Anonymize IP
      'aip': 1,

      'tid': self.tracking_id,

      # Random UUID
      'cid': self.config.get('client_id'),

      'cd1': self.os_name,

      # GA custom dimension 2 = Python Version, scope = Session
      'cd2': self.python_version,

      # GA custom dimension 3 = App Version, scope = Session
      'cd3': self.app_version,

      # Cache busting, need to be last param sent
      'z': now_ms
    }

    # Set payload data based on the tracking type.
    if payload['type'] == 'event':
      qs['ec'] = payload['category']
      qs['ea'] = payload['action']
      if 'label' in payload:
        qs['el'] = payload['label']
      if 'value' in payload:
        qs['ev'] = payload['value']
    else:
      qs['dp'] = payload['path']

    # Sends the request.
    try:
      requests.post(self.URL, data=qs, timeout=5)
    except requests.exceptions.RequestException:
      pass

  def track(self, *args):
    if self.opt_out is True:
      return
    only_args = filter(lambda x: not x.startswith('-'), args)
    path = '/' + '/'.join(map(lambda x: x.replace(' ', '-'), only_args))
    payload = {'type': 'pageview', 'path': path}
    self._send(payload)

  def track_event(self, **kwargs):
    if self.opt_out is True:
      return
    if any([not kwargs, 'category' not in kwargs, 'action' not in kwargs]):
      print('`category` and `action` required for anonymous reporting')
      return
    payload = {'type': 'event'}
    payload.update(kwargs)
    self._send(payload)
