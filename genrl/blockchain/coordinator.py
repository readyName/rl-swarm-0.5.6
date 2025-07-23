import json
from abc import ABC

import requests

from genrl.blockchain.connections import (
    send_chain_txn,
    send_via_api,
    setup_account,
    setup_web3,
)
from genrl.logging_utils.global_defs import get_logger

SWARM_COORDINATOR_VERSION = "0.4.2"
SWARM_COORDINATOR_ABI_JSON = (
    f"hivemind_exp/contracts/SwarmCoordinator_{SWARM_COORDINATOR_VERSION}.json"
)

logger = get_logger()


class SwarmCoordinator(ABC):
    def __init__(self, web3_url: str, contract_address: str, **kwargs) -> None:
        self.web3 = setup_web3(web3_url)
        with open(SWARM_COORDINATOR_ABI_JSON, "r") as f:
            contract_abi = json.load(f)["abi"]

        self.contract = self.web3.eth.contract(address=contract_address, abi=contract_abi)  # type: ignore
        super().__init__(**kwargs)

    def register_peer(self, peer_id): ...

    def submit_winners(self, round_num, winners, peer_id): ...

    def submit_reward(self, round_num, stage_num, reward, peer_id): ...

    def get_bootnodes(self):
        return self.contract.functions.getBootnodes().call()

    def get_round_and_stage(self):
        with self.web3.batch_requests() as batch:
            batch.add(self.contract.functions.currentRound())
            batch.add(self.contract.functions.currentStage())
            round_num, stage_num = batch.execute()

        return round_num, stage_num


class WalletSwarmCoordinator(SwarmCoordinator):
    def __init__(
        self, web3_url: str, contract_address: str, private_key: str, chain_id: int
    ) -> None:
        super().__init__(web3_url, contract_address)
        self.account = setup_account(self.web3, private_key)
        self.chain_id = chain_id

    def _default_gas(self):
        return {
            "gas": 2000000,
            "gasPrice": self.web3.to_wei("5", "gwei"),
        }

    def register_peer(self, peer_id):
        send_chain_txn(
            self.web3,
            self.account,
            lambda: self.contract.functions.registerPeer(peer_id).build_transaction(
                self._default_gas()
            ),
            chain_id=self.chain_id,
        )

    def submit_winners(self, round_num, winners, peer_id):
        send_chain_txn(
            self.web3,
            self.account,
            lambda: self.contract.functions.submitWinners(
                round_num, winners, peer_id
            ).build_transaction(self._default_gas()),
            chain_id=self.chain_id,
        )

    def submit_reward(self, round_num, stage_num, reward, peer_id):
        send_chain_txn(
            self.web3,
            self.account,
            lambda: self.contract.functions.submitReward(
                round_num, stage_num, reward, peer_id
            ).build_transaction(self._default_gas()),
            chain_id=self.chain_id,
        )


# TODO: Uncomment detailed logs once you can disambiguate 500 errors.
class ModalSwarmCoordinator(SwarmCoordinator):
    def __init__(
        self, web3_url: str, contract_address: str, org_id: str, modal_proxy_url: str
    ) -> None:
        super().__init__(web3_url, contract_address)
        self.org_id = org_id
        self.modal_proxy_url = modal_proxy_url

    def register_peer(self, peer_id):
        try:
            send_via_api(
                self.org_id, self.modal_proxy_url, "register-peer", {"peerId": peer_id}
            )
        except requests.exceptions.HTTPError as http_err:
            if http_err.response is None or http_err.response.status_code != 400:
                raise

            try:
                err_data = http_err.response.json()
                err_name = err_data["error"]
                if err_name != "PeerIdAlreadyRegistered":
                    logger.info(f"Registering peer failed with: f{err_name}")
                    raise
                logger.info(f"Peer ID [{peer_id}] is already registered! Continuing.")

            except json.JSONDecodeError as decode_err:
                logger.debug(
                    "Error decoding JSON during handling of register-peer error"
                )
                raise http_err

    def submit_reward(self, round_num, stage_num, reward, peer_id):
        try:
            send_via_api(
                self.org_id,
                self.modal_proxy_url,
                "submit-reward",
                {
                    "roundNumber": round_num,
                    "stageNumber": stage_num,
                    "reward": reward,
                    "peerId": peer_id,
                },
            )
        except requests.exceptions.HTTPError as e:
            if e.response is None or e.response.status_code != 500:
                raise

            logger.debug("Unknown error calling submit_reward endpoint! Continuing.")
            # logger.info("Reward already submitted for this round/stage! Continuing.")

    def submit_winners(self, round_num, winners, peer_id):
        try:
            send_via_api(
                self.org_id,
                self.modal_proxy_url,
                "submit-winner",
                {"roundNumber": round_num, "winners": winners, "peerId": peer_id},
            )
        except requests.exceptions.HTTPError as e:
            if e.response is None or e.response.status_code != 500:
                raise

            logger.debug("Unknown error calling submit-winner endpoint! Continuing.")
