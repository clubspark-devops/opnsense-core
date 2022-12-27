<?php

/*
 * Copyright (C) 2022 Deciso B.V.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 * OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

namespace OPNsense\IPsec;

use Phalcon\Messages\Message;
use OPNsense\Base\BaseModel;
use OPNsense\Firewall\Util;

/**
 * Class Swanctl
 * @package OPNsense\IPsec
 */
class Swanctl extends BaseModel
{
    /**
     * {@inheritdoc}
     */
    public function performValidation($validateFullModel = false)
    {
        $messages = parent::performValidation($validateFullModel);
        $vtis = [];

        foreach ($this->getFlatNodes() as $key => $node) {
            if ($validateFullModel || $node->isFieldChanged()) {
                $tagName = $node->getInternalXMLTagName();
                $parentNode = $node->getParentNode();
                $parentKey = $parentNode->__reference;
                $parentTagName = $parentNode->getInternalXMLTagName();
                if ($parentTagName === 'VTI') {
                    $vtis[$parentKey] = $parentNode;
                }
            }
        }
        foreach ($vtis as $key => $node) {
            $vti_inets = [];
            foreach (['local', 'remote', 'tunnel_local', 'tunnel_remote'] as $prop) {
                $vti_inets[$prop] = strpos((string)$node->$prop, ':') > 0 ? 'inet6' : 'inet';
            }

            if ($vti_inets['local'] != $vti_inets['remote']) {
                $messages->appendMessage(new Message(gettext("Protocol families should match"), $key . ".local"));
            }
            if ($vti_inets['tunnel_local'] != $vti_inets['tunnel_remote']) {
                $messages->appendMessage(new Message(gettext("Protocol families should match"), $key . ".tunnel_local"));
            }
        }

        return $messages;
    }

    /**
     * @return boolean enc0 enabled (any policy set)
     */
    public function isEnabled()
    {
        foreach ($this->Connections->Connection->iterateItems() as $node_uuid => $node) {
            if (!empty((string)$node->enabled)) {
                return true;
            }
        }
        return false;
    }

    /**
     * generate swanctl configuration output, containing "pools" and "connections", locals, remotes and children
     * are treated as children of connection.
     * @return array
     */
    public function getConfig()
    {
        $data = ['connections' => [], 'pools' => []];
        $references = [
            'pools' => 'Pools.Pool',
            'connections' => 'Connections.Connection',
            'local' => 'locals.local',
            'remote' => 'remotes.remote',
            'children' => 'children.child',
        ];
        $pool_names = [];
        foreach ($references as $key => $ref) {
            foreach ($this->getNodeByReference($ref)->iterateItems() as $node_uuid => $node) {
                if (empty((string)$node->enabled)) {
                    continue;
                }
                $parent = null;
                $thisnode = [];
                foreach ($node->iterateItems() as $attr_name => $attr) {
                    if ($attr_name == 'connection' && isset($data['connections'][(string)$attr])) {
                        $parent = (string)$attr;
                        continue;
                    } elseif ($attr_name == 'pools') {
                        // pools are mapped by name for clearer identification and legacy support
                        if ((string)$attr != '') {
                            $pools = [];
                            foreach (explode(',', (string)$attr) as $pool_id) {
                                $is_uuid = preg_match(
                                    '/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/',
                                    $pool_id
                                ) == 1;
                                if (isset($pool_names[$pool_id])) {
                                    $pools[] = $pool_names[$pool_id];
                                } elseif (!$is_uuid) {
                                    $pools[] = $pool_id;
                                }
                            }
                            if (!empty($pools)) {
                                $thisnode['pools'] = implode(',', $pools);
                            }
                        }
                        continue;
                    } elseif ($attr_name == 'enabled') {
                        if (empty((string)$attr)) {
                            // disabled entity
                            $thisnode = [];
                            break;
                        } else {
                            continue;
                        }
                    } elseif ((string)$attr == '') {
                        continue;
                    } elseif (in_array($attr_name, ['name', 'description'])) {
                        if ($key == 'pools') {
                            $pool_names[$node_uuid] = (string)$attr;
                        }
                        continue;
                    } elseif (is_a($attr, 'OPNsense\Base\FieldTypes\BooleanField')) {
                        $thisnode[$attr_name] = (string)$attr == '1' ? 'yes' : 'no';
                    } elseif (is_a($attr, 'OPNsense\Base\FieldTypes\CertificateField')) {
                        $tmp = [];
                        foreach (explode(',', (string)$attr) as $item) {
                            $tmp[] = $item . '.crt';
                        }
                        $thisnode[$attr_name] = implode(',', $tmp);
                    } elseif ($attr_name == 'pubkeys') {
                        $tmp = [];
                        foreach (explode(',', (string)$attr) as $item) {
                            $tmp[] = $item . '.pem';
                        }
                        $thisnode[$attr_name] = implode(',', $tmp);
                    } else {
                        $thisnode[$attr_name] = (string)$attr;
                    }
                }
                if (empty($thisnode)) {
                    continue;
                } elseif (!empty($parent)) {
                    if ($key == 'children') {
                        if (!isset($data['connections'][$parent]['children'])) {
                            $data['connections'][$parent]['children'] = [];
                        }
                        if (!empty($thisnode['reqid'])) {
                            // trigger updown event handler when a reqid is set.
                            // currently this only handles manual spd entries, we may extend/refactor the script later
                            // if needed
                            $thisnode['updown'] = '/usr/local/opnsense/scripts/ipsec/updown_event.py';
                        }
                        $data['connections'][$parent]['children'][$node_uuid] = $thisnode;
                    } else {
                        $data['connections'][$parent][$key . '-' . $node_uuid] = $thisnode;
                    }
                } elseif (in_array($key, ['connections', 'pools'])) {
                    if (!isset($data[$key])) {
                        $data[$key] = [];
                    }
                    $data[$key][$node_uuid] = $thisnode;
                }
            }
        }
        return $data;
    }

    /**
     * return non legacy vti devices formatted like ipsec_get_configured_vtis()
     */
    public function getVtiDevices()
    {
        $result = [];
        foreach ($this->VTIs->VTI->iterateItems() as $node_uuid => $node) {
            if ((string)$node->origin != 'legacy' && (string)$node->enabled == '1') {
                $inet = strpos((string)$node->local_tunnel, ':') > 0 ? 'inet6' : 'inet';
                $result['ipsec' . (string)$node->reqid] = [
                    'reqid' => (string)$node->reqid,
                    'local' => (string)$node->local,
                    'remote' => (string)$node->remote,
                    'descr' => (string)$node->description,
                    'networks' => [
                        [
                            'inet' => $inet,
                            'tunnel_local' => (string)$node->tunnel_local,
                            'tunnel_remote' => (string)$node->tunnel_remote,
                            'mask' => Util::smallestCIDR(
                                [(string)$node->tunnel_local, (string)$node->tunnel_remote],
                                $inet
                            )
                        ]
                    ]
                ];
            }
        }
        return $result;
    }

    public function getUsedCertrefs()
    {
        $references = [
            'locals' => 'locals.local',
            'remotes' => 'remotes.remote',
        ];
        $certrefs = [];
        foreach ($references as $key => $ref) {
            foreach ($this->getNodeByReference($ref)->iterateItems() as $node_uuid => $node) {
                if (empty((string)$node->enabled)) {
                    continue;
                } elseif (!empty((string)$node->certs)) {
                    foreach (explode(',', (string)$node->certs) as $cert) {
                        if (!in_array($cert, $certrefs)) {
                            $certrefs[] = $cert;
                        }
                    }
                }
            }
        }
        return $certrefs;
    }
}
