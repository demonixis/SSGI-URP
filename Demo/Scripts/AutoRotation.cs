using UnityEngine;

namespace Demonixis.Toolbox.Rendering.Demo
{
    public class AutoRotation : MonoBehaviour
    {
        [SerializeField]
        private Vector3 m_RotationVector;

        void Update() => transform.Rotate(m_RotationVector);
    }
}