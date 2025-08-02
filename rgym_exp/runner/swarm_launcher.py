import os

import hydra
from genrl.communication.communication import Communication
from genrl.communication.hivemind.hivemind_backend import (
    HivemindBackend,
    HivemindRendezvouz,
)
from hydra.utils import instantiate
from omegaconf import DictConfig, OmegaConf

from rgym_exp.src.utils.omega_gpu_resolver import (
    gpu_model_choice_resolver,
)  # necessary for gpu_model_choice resolver in hydra config


@hydra.main(version_base=None)
def main(cfg: DictConfig):
    is_master = False
    HivemindRendezvouz.init(is_master=is_master)

    try:

        print("======================================")
        print("======================================")
        print("======================================")
        print("======================================")
        print("准备测试进程退出")
        time.sleep(3)
        os._exit(1)
        game_manager = instantiate(cfg.game_manager)
        game_manager.run_game()
    except Exception as e:
        import traceback
        print("[swarm_launcher] Caught exception:")
        traceback.print_exc()

        # 强制退出进程，触发容器退出
        os._exit(1)

if __name__ == "__main__":
    os.environ["HYDRA_FULL_ERROR"] = "1"
    Communication.set_backend(HivemindBackend)
    main()
